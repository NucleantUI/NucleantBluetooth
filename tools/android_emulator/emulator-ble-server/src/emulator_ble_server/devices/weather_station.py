"""Weather Station: environmental readings, in GATT and in its advertisement."""

import math
import struct

import reactivex as rx
from bumble.core import AdvertisingData
from bumble.gatt import Characteristic, Service
from reactivex import operators as ops

from ..peripheral import Peripheral
from ..signals import Signal, Steady
from ..values import uuid16

ENVIRONMENTAL_SENSING = 0x181A


class WeatherStation(Peripheral):
    """Environmental Sensing: readings that notify, and the temperature in
    the advertisement too.

    - Temperature (0.01 °C), Humidity (0.01 %) and Pressure (0.1 Pa) read
      and notify every 2 seconds, on slow waves a few minutes long.
    - The advertisement carries the temperature as service data for
      Environmental Sensing, updated every 10 seconds: a scanner sees the
      service data change while it scans.
    """

    slug = "weather-station"

    def __init__(self, address: str, signal: Signal | None = None) -> None:
        # Outside, through a wall: weak and flickering.
        super().__init__("Weather Station", address, signal or Steady(-84, jitter=4, period=1))
        self.advertised_temperature = 21.0
        readable = Characteristic.Properties.READ | Characteristic.Properties.NOTIFY
        self.temperature = Characteristic(uuid16(0x2A6E), readable, Characteristic.READABLE, struct.pack("<h", 2100))
        self.humidity = Characteristic(uuid16(0x2A6F), readable, Characteristic.READABLE, struct.pack("<H", 4500))
        self.pressure = Characteristic(uuid16(0x2A6D), readable, Characteristic.READABLE, struct.pack("<I", 1013250))

    def services(self) -> list[Service]:
        return [Service(uuid16(ENVIRONMENTAL_SENSING), [self.temperature, self.humidity, self.pressure])]

    def advertisement(self) -> AdvertisingData:
        return AdvertisingData([
            (AdvertisingData.FLAGS, bytes([0x06])),
            (AdvertisingData.COMPLETE_LOCAL_NAME, self.name.encode()),
            (
                AdvertisingData.SERVICE_DATA_16_BIT_UUID,
                struct.pack("<Hh", ENVIRONMENTAL_SENSING, round(self.advertised_temperature * 100)),
            ),
        ])

    def behave(self) -> None:
        readings = rx.interval(2.0).pipe(ops.map(lambda tick: weather(tick * 2.0)), ops.share())
        self.run(readings, self._publish)
        self.run(readings.pipe(ops.sample(10.0)), self._advertise_temperature)

    def _publish(self, reading: tuple[float, float, float]) -> None:
        temperature, humidity, pressure = reading
        self.notify(self.temperature, struct.pack("<h", round(temperature * 100)))
        self.notify(self.humidity, struct.pack("<H", round(humidity * 100)))
        self.notify(self.pressure, struct.pack("<I", round(pressure * 10)))

    def _advertise_temperature(self, reading: tuple[float, float, float]) -> None:
        self.advertised_temperature = reading[0]
        self.readvertise()


def weather(seconds: float) -> tuple[float, float, float]:
    """Temperature (°C), humidity (%) and pressure (Pa) `seconds` in."""
    temperature = 21 + 4 * math.sin(seconds / 120)
    humidity = 50 - 15 * math.sin(seconds / 120 + 0.5)
    pressure = 101325 + 800 * math.sin(seconds / 300)
    return temperature, humidity, pressure

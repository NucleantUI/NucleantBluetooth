"""Pulse HR: a heart rate chest strap."""

import random

import reactivex as rx
from bumble.att import ATT_Error
from bumble.core import AdvertisingData
from bumble.gatt import Characteristic, CharacteristicValue, Service
from reactivex import operators as ops
from reactivex.subject import Subject

from ..peripheral import Peripheral
from ..signals import Orbiting, Signal
from ..values import heart_rate_measurement, manufacturer_data, uuid16

NORDIC_SEMICONDUCTOR = 0x0059


class HeartRateMonitor(Peripheral):
    """A chest strap: Heart Rate, Battery and Device Information, the
    standard services, with a rate that wanders and a battery that drains.

    - Heart Rate Measurement notifies every second: a rate that wanders
      between 55 and 175 bpm, and the energy expended since the last reset.
    - Heart Rate Control Point takes `01`, which resets the energy;
      anything else is refused with ATT error 0x80.
    - Body Sensor Location reads Chest.
    - Battery Level reads and notifies, a percent less every 10 seconds,
      back to 100 after 5.
    - Advertises its name, both services, its appearance and its transmit
      power; the scan response has Nordic's manufacturer data.
    """

    slug = "heart-rate"

    def __init__(self, address: str, signal: Signal | None = None) -> None:
        # Worn by someone walking round the room.
        super().__init__("Pulse HR", address, signal or Orbiting(far=-78, near=-45, period=40))
        self.energy_resets: Subject[None] = Subject()
        self.measurement = Characteristic(
            uuid16(0x2A37), Characteristic.Properties.NOTIFY, Characteristic.READABLE,
            heart_rate_measurement(72, 0),
        )
        self.battery = Characteristic(
            uuid16(0x2A19), Characteristic.Properties.READ | Characteristic.Properties.NOTIFY,
            Characteristic.READABLE, bytes([100]),
        )

    def services(self) -> list[Service]:
        return [
            Service(uuid16(0x180D), [
                self.measurement,
                Characteristic(uuid16(0x2A38), Characteristic.Properties.READ, Characteristic.READABLE, bytes([1])),
                Characteristic(
                    uuid16(0x2A39), Characteristic.Properties.WRITE, Characteristic.WRITEABLE,
                    CharacteristicValue(write=self._control),
                ),
            ]),
            Service(uuid16(0x180F), [self.battery]),
            Service(uuid16(0x180A), [
                Characteristic(uuid16(0x2A29), Characteristic.Properties.READ, Characteristic.READABLE, b"NucleantUI"),
                Characteristic(uuid16(0x2A24), Characteristic.Properties.READ, Characteristic.READABLE, b"Pulse HR"),
                Characteristic(uuid16(0x2A25), Characteristic.Properties.READ, Characteristic.READABLE, b"PHR-0001"),
                Characteristic(uuid16(0x2A26), Characteristic.Properties.READ, Characteristic.READABLE, b"1.2.3"),
            ]),
        ]

    def advertisement(self) -> AdvertisingData:
        return AdvertisingData([
            (AdvertisingData.FLAGS, bytes([0x06])),
            (AdvertisingData.COMPLETE_LOCAL_NAME, self.name.encode()),
            (AdvertisingData.COMPLETE_LIST_OF_16_BIT_SERVICE_CLASS_UUIDS, bytes([0x0D, 0x18, 0x0F, 0x18])),
            # Heart Rate Sensor: Heart Rate Belt.
            (AdvertisingData.APPEARANCE, (0x0341).to_bytes(2, "little")),
            (AdvertisingData.TX_POWER_LEVEL, (-4).to_bytes(1, "little", signed=True)),
        ])

    def scan_response(self) -> AdvertisingData:
        return AdvertisingData([
            (AdvertisingData.MANUFACTURER_SPECIFIC_DATA, manufacturer_data(NORDIC_SEMICONDUCTOR, b"\x01\x02\x03")),
        ])

    def behave(self) -> None:
        seconds = rx.interval(1.0)
        heart_rate = seconds.pipe(ops.scan(lambda bpm, _: wander(bpm), 72))
        # Kilojoules, one more each second, from 0 again on every reset.
        energy = self.energy_resets.pipe(
            ops.start_with(None),
            ops.map(lambda _: seconds.pipe(ops.scan(lambda kj, _: kj + 1, 0), ops.start_with(0))),
            ops.switch_latest(),
        )
        self.run(
            heart_rate.pipe(ops.with_latest_from(energy)),
            lambda reading: self.notify(self.measurement, heart_rate_measurement(*reading)),
        )
        self.run(
            rx.interval(10.0).pipe(ops.scan(lambda level, _: 100 if level <= 5 else level - 1, 100)),
            lambda level: self.notify(self.battery, bytes([level])),
        )

    def _control(self, connection, value: bytes) -> None:
        if bytes(value) != b"\x01":
            # Heart Rate's "Control Point Not Supported".
            raise ATT_Error(0x80)
        self.log.info("%s: energy expended reset", self.name)
        self.energy_resets.on_next(None)


def wander(bpm: int) -> int:
    """The next second's rate: a step either way, now and then a sprint."""
    step = random.choice([-2, -1, -1, 0, 0, 1, 1, 2])
    if random.random() < 0.02:
        step += 25
    return max(55, min(175, bpm + step))

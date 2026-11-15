"""Thermo: a body thermometer that indicates its measurements."""

import math
import random
import struct

import reactivex as rx
from bumble.att import ATT_Error, ErrorCode
from bumble.core import AdvertisingData
from bumble.gatt import Characteristic, CharacteristicValue, Service
from reactivex import operators as ops
from reactivex.subject import BehaviorSubject

from ..peripheral import Peripheral
from ..signals import Signal, Steady
from ..values import ieee11073_float, uuid16


class Thermometer(Peripheral):
    """A body thermometer: Health Thermometer, measurements indicated, and
    a measurement interval a central can write.

    - Temperature Measurement indicates (each one confirmed by the central)
      a body temperature in °C, an IEEE-11073 float, with a slow fever coming
      and going.
    - Measurement Interval reads, writes and indicates the seconds between
      measurements, 1 to 60. A write retimes the measurements at once; a
      value out of range is refused with ATT error 0xFF (Out of Range).
    - Temperature Type reads Body (general).
    """

    slug = "thermometer"

    def __init__(self, address: str, signal: Signal | None = None) -> None:
        # On the bedside table: barely changes.
        super().__init__("Thermo", address, signal or Steady(-58, jitter=1))
        self.interval = BehaviorSubject(2)
        self.measurement = Characteristic(
            uuid16(0x2A1C), Characteristic.Properties.INDICATE, Characteristic.READABLE, b"",
        )
        self.interval_characteristic = Characteristic(
            uuid16(0x2A21),
            Characteristic.Properties.READ | Characteristic.Properties.WRITE | Characteristic.Properties.INDICATE,
            Characteristic.READABLE | Characteristic.WRITEABLE,
            CharacteristicValue(read=self._read_interval, write=self._write_interval),
        )

    def services(self) -> list[Service]:
        return [
            Service(uuid16(0x1809), [
                self.measurement,
                Characteristic(uuid16(0x2A1D), Characteristic.Properties.READ, Characteristic.READABLE, bytes([2])),
                self.interval_characteristic,
            ]),
        ]

    def advertisement(self) -> AdvertisingData:
        return AdvertisingData([
            (AdvertisingData.FLAGS, bytes([0x06])),
            (AdvertisingData.COMPLETE_LOCAL_NAME, self.name.encode()),
            (AdvertisingData.COMPLETE_LIST_OF_16_BIT_SERVICE_CLASS_UUIDS, bytes([0x09, 0x18])),
            # Thermometer: Ear.
            (AdvertisingData.APPEARANCE, (0x0301).to_bytes(2, "little")),
        ])

    def behave(self) -> None:
        # The interval that is set now decides when the next one comes.
        measurements = self.interval.pipe(
            ops.map(lambda seconds: rx.interval(float(seconds))),
            ops.switch_latest(),
            ops.scan(lambda count, _: count + 1, 0),
            ops.map(body_temperature),
        )
        self.run(measurements, lambda celsius: self.indicate(self.measurement, b"\x00" + ieee11073_float(celsius)))

    def _read_interval(self, connection) -> bytes:
        return struct.pack("<H", self.interval.value)

    def _write_interval(self, connection, value: bytes) -> None:
        if len(value) != 2:
            raise ATT_Error(ErrorCode.INVALID_ATTRIBUTE_LENGTH)
        (seconds,) = struct.unpack("<H", value)
        if not 1 <= seconds <= 60:
            raise ATT_Error(ErrorCode.OUT_OF_RANGE)
        self.log.info("%s: measuring every %d s", self.name, seconds)
        self.interval.on_next(seconds)
        self.indicate(self.interval_characteristic, bytes(value))


def body_temperature(count: int) -> float:
    """36.8 °C, a fever up to 39 °C every few minutes, and a little noise."""
    fever = max(0.0, math.sin(count / 40)) * 2.2
    return round(36.8 + fever + random.uniform(-0.05, 0.05), 2)

"""Test Bench: a characteristic for each way a request can go."""

import struct

import reactivex as rx
from bumble.att import ATT_Error, ErrorCode
from bumble.gatt import Characteristic, CharacteristicValue, Service
from reactivex import operators as ops

from ..peripheral import Peripheral
from ..signals import Signal, Steady
from ..values import custom_uuid

BIG_VALUE = bytes(range(256)) + bytes(range(144))


class TestBench(Peripheral):
    """A characteristic for each way a request can go: fast notifications,
    a long read, refused reads and writes, writes without response and
    indications.

    In one service of its own, `7E5700AB-0000-…`, its characteristics
    numbered:

    1. Counter (read, notify): a 32-bit count, 4 a second.
    2. Big Value (read): 400 bytes, more than one ATT packet: a long read.
    3. Locked (read): every read refused, Read Not Permitted (0x02).
    4. Picky (read, write): one byte or the write is refused, Invalid
       Attribute Value Length (0x0D).
    5. Rejects Writes (write): every write refused, Write Request
       Rejected (0xFC).
    6. Fire and Forget (write without response only): counted in 7.
    7. Writes Received (read, notify): how many writes 6 took.
    8. Alarm (indicate only): a count every 7 seconds, each confirmed.
    """

    slug = "test-bench"
    #: Not a pytest test class, whatever its name says.
    __test__ = False

    def __init__(self, address: str, signal: Signal | None = None) -> None:
        # Right next to the phone.
        super().__init__("Test Bench", address, signal or Steady(-42, jitter=0.5))
        properties = Characteristic.Properties
        self.picky = b"\x00"
        self.writes_received = 0
        self.counter = Characteristic(
            self._uuid(1), properties.READ | properties.NOTIFY, Characteristic.READABLE, struct.pack("<I", 0),
        )
        self.writes = Characteristic(
            self._uuid(7), properties.READ | properties.NOTIFY, Characteristic.READABLE, struct.pack("<I", 0),
        )
        self.alarm = Characteristic(self._uuid(8), properties.INDICATE, Characteristic.READABLE, b"")
        self.characteristics = [
            self.counter,
            Characteristic(self._uuid(2), properties.READ, Characteristic.READABLE, BIG_VALUE),
            Characteristic(
                self._uuid(3), properties.READ, Characteristic.READABLE,
                CharacteristicValue(read=self._refuse_read),
            ),
            Characteristic(
                self._uuid(4), properties.READ | properties.WRITE,
                Characteristic.READABLE | Characteristic.WRITEABLE,
                CharacteristicValue(read=lambda connection: self.picky, write=self._write_picky),
            ),
            Characteristic(
                self._uuid(5), properties.WRITE, Characteristic.WRITEABLE,
                CharacteristicValue(write=self._refuse_write),
            ),
            Characteristic(
                self._uuid(6), properties.WRITE_WITHOUT_RESPONSE, Characteristic.WRITEABLE,
                CharacteristicValue(write=self._count_write),
            ),
            self.writes,
            self.alarm,
        ]

    @staticmethod
    def _uuid(number: int):
        return custom_uuid(0xAB, number)

    def services(self) -> list[Service]:
        return [Service(self._uuid(0), self.characteristics)]

    def behave(self) -> None:
        self.run(rx.interval(0.25), lambda count: self.notify(self.counter, struct.pack("<I", count + 1)))
        self.run(
            rx.interval(7.0).pipe(ops.map(lambda count: count + 1)),
            lambda count: self.indicate(self.alarm, bytes([count & 0xFF])),
        )

    def _refuse_read(self, connection) -> bytes:
        raise ATT_Error(ErrorCode.READ_NOT_PERMITTED)

    def _write_picky(self, connection, value: bytes) -> None:
        if len(value) != 1:
            raise ATT_Error(ErrorCode.INVALID_ATTRIBUTE_LENGTH)
        self.picky = bytes(value)

    def _refuse_write(self, connection, value: bytes) -> None:
        raise ATT_Error(ErrorCode.WRITE_REQUEST_REJECTED)

    def _count_write(self, connection, value: bytes) -> None:
        self.writes_received += 1
        self.notify(self.writes, struct.pack("<I", self.writes_received))

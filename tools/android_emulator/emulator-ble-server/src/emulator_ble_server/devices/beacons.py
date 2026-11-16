"""Beacons: devices that only advertise. No name, no connections."""

import time
import uuid

import reactivex as rx
from bumble.core import AdvertisingData
from reactivex import operators as ops

from ..peripheral import Peripheral
from ..signals import Orbiting, Signal, Steady
from ..values import eddystone_tlm, eddystone_url, ibeacon, manufacturer_data

APPLE = 0x004C
EDDYSTONE = 0xFEAA


class IBeacon(Peripheral):
    """An iBeacon: non-connectable, no name, Apple's manufacturer data with a
    proximity UUID, major 1 and a minor that counts up every 15 seconds."""

    slug = "ibeacon"
    connectable = False
    proximity_uuid = uuid.UUID("E2C56DB5-DFFB-48D2-B060-D0F5A71096E0")

    def __init__(self, address: str, signal: Signal | None = None) -> None:
        # Fixed to the ceiling, noisy.
        super().__init__("iBeacon", address, signal or Steady(-70, jitter=4))
        self.minor = 1

    def advertisement(self) -> AdvertisingData:
        return AdvertisingData([
            (AdvertisingData.FLAGS, bytes([0x06])),
            (
                AdvertisingData.MANUFACTURER_SPECIFIC_DATA,
                manufacturer_data(APPLE, ibeacon(self.proximity_uuid, major=1, minor=self.minor)),
            ),
        ])

    def behave(self) -> None:
        self.run(rx.interval(15.0), self._next_minor)

    def _next_minor(self, _) -> None:
        self.minor += 1
        self.readvertise()


class Eddystone(Peripheral):
    """An Eddystone beacon: non-connectable, no name, the Eddystone service
    in its list and service data that switches every 5 seconds between a URL
    frame and a telemetry frame (battery, temperature, count, uptime)."""

    slug = "eddystone"
    connectable = False
    url = "https://github.com/NucleantUI"

    def __init__(self, address: str, signal: Signal | None = None) -> None:
        # On a delivery robot doing laps.
        super().__init__("Eddystone", address, signal or Orbiting(far=-90, near=-60, period=70))
        self.frame = eddystone_url(self.url)
        self.started = time.monotonic()

    def advertisement(self) -> AdvertisingData:
        return AdvertisingData([
            (AdvertisingData.FLAGS, bytes([0x06])),
            (AdvertisingData.COMPLETE_LIST_OF_16_BIT_SERVICE_CLASS_UUIDS, EDDYSTONE.to_bytes(2, "little")),
            (AdvertisingData.SERVICE_DATA_16_BIT_UUID, EDDYSTONE.to_bytes(2, "little") + self.frame),
        ])

    def behave(self) -> None:
        self.run(rx.interval(5.0).pipe(ops.scan(lambda count, _: count + 1, 0)), self._next_frame)

    def _next_frame(self, count: int) -> None:
        if count % 2:
            uptime = time.monotonic() - self.started
            self.frame = eddystone_tlm(
                battery_mv=3000 - count, temperature=22.5, advertisements=count * 50, uptime_s=uptime,
            )
        else:
            self.frame = eddystone_url(self.url)
        self.readvertise()

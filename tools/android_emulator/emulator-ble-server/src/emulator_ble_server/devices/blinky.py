"""Blinky Tag: a tag that advertises in bursts."""

import struct

import reactivex as rx
from bumble.gatt import Characteristic, Service
from reactivex import operators as ops

from ..peripheral import Peripheral
from ..signals import Drifting, Signal
from ..values import custom_uuid

ON_SECONDS = 3
CYCLE_SECONDS = 8


class BlinkyTag(Peripheral):
    """Advertises for 3 seconds, then nothing for 5, over and over: a
    scanner sees it come and go, and its last-seen time fall behind.
    Connectable while it advertises; its one characteristic, Blinks (read,
    notify), counts the bursts."""

    slug = "blinky"

    def __init__(self, address: str, signal: Signal | None = None) -> None:
        # On a keyring that moves about a lot.
        super().__init__("Blinky Tag", address, signal or Drifting(weakest=-85, strongest=-45, step=6))
        self.blinks = Characteristic(
            custom_uuid(0xB1, 1), Characteristic.Properties.READ | Characteristic.Properties.NOTIFY,
            Characteristic.READABLE, struct.pack("<I", 0),
        )

    def services(self) -> list[Service]:
        return [Service(custom_uuid(0xB1, 0), [self.blinks])]

    def behave(self) -> None:
        advertising = rx.interval(1.0).pipe(
            ops.map(lambda second: (second + 1) % CYCLE_SECONDS < ON_SECONDS),
            ops.start_with(True),
            ops.distinct_until_changed(),
        )
        self.run(advertising, self._switch)
        self.run(
            advertising.pipe(ops.filter(bool), ops.scan(lambda count, _: count + 1, 0)),
            lambda count: self.notify(self.blinks, struct.pack("<I", count)),
        )

    def _switch(self, on: bool) -> None:
        self.spawn(self.go_quiet(not on))

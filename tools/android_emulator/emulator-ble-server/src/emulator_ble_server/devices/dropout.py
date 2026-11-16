"""Dropout: a device that ends every connection itself."""

import reactivex as rx
from bumble.device import Connection
from bumble.gatt import Characteristic, Service
from reactivex import operators as ops

from ..peripheral import Peripheral
from ..signals import Drifting, Signal
from ..values import custom_uuid

GRACE_SECONDS = 12


class Dropout(Peripheral):
    """Accepts a connection, counts down 12 seconds on Seconds Left (read,
    notify), then disconnects: the central sees a connection it did not
    end (remote user terminated, HCI 0x13)."""

    slug = "dropout"

    def __init__(self, address: str, signal: Signal | None = None) -> None:
        super().__init__("Dropout", address, signal or Drifting(weakest=-88, strongest=-55, step=3))
        self.seconds_left = Characteristic(
            custom_uuid(0xD0, 1), Characteristic.Properties.READ | Characteristic.Properties.NOTIFY,
            Characteristic.READABLE, bytes([GRACE_SECONDS]),
        )

    def services(self) -> list[Service]:
        return [Service(custom_uuid(0xD0, 0), [self.seconds_left])]

    def behave(self) -> None:
        self.run(self.connections, self._count_down)

    def _count_down(self, connection: Connection) -> None:
        self.seconds_left.value = bytes([GRACE_SECONDS])
        countdown = rx.interval(1.0).pipe(
            ops.map(lambda second: GRACE_SECONDS - 1 - second),
            ops.take(GRACE_SECONDS),
            self.until_disconnected(connection),
        )
        self.keep(countdown.subscribe(
            on_next=lambda left: self.notify(self.seconds_left, bytes([left])),
            on_completed=lambda: self.spawn(self._drop(connection)),
            scheduler=self.scheduler,
        ))

    async def _drop(self, connection: Connection) -> None:
        if self.device is None or connection.handle not in self.device.connections:
            return
        self.log.info("%s: dropping %s", self.name, connection.peer_address)
        await connection.disconnect()

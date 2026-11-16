"""UART Console: Nordic's UART service, a text console over GATT."""

import reactivex as rx
from bumble.core import UUID, AdvertisingData
from bumble.gatt import Characteristic, CharacteristicValue, Service
from reactivex import operators as ops
from reactivex.subject import Subject

from ..peripheral import Peripheral
from ..signals import Signal, Steady

UART_SERVICE = UUID("6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
UART_RX = UUID("6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
UART_TX = UUID("6E400003-B5A3-F393-E0A9-E50E24DCCA9E")

#: What fits one notification at the default ATT MTU (23 − 3).
NOTIFICATION_BYTES = 20


class UartConsole(Peripheral):
    """A text console over Nordic UART: 128-bit UUIDs, writes both ways,
    echoes.

    - RX takes writes with and without response; each line comes back
      upper-cased on TX.
    - TX notifies those echoes, and `tick N` every 5 seconds.
    - Advertises its name; the 128-bit service is in the scan response.
    """

    slug = "uart"

    def __init__(self, address: str, signal: Signal | None = None) -> None:
        # A board on the desk.
        super().__init__("UART Console", address, signal or Steady(-50, jitter=1))
        self.lines: Subject[bytes] = Subject()
        self.tx = Characteristic(UART_TX, Characteristic.Properties.NOTIFY, Characteristic.READABLE, b"")

    def services(self) -> list[Service]:
        return [
            Service(UART_SERVICE, [
                Characteristic(
                    UART_RX,
                    Characteristic.Properties.WRITE | Characteristic.Properties.WRITE_WITHOUT_RESPONSE,
                    Characteristic.WRITEABLE,
                    CharacteristicValue(write=lambda connection, value: self.lines.on_next(bytes(value))),
                ),
                self.tx,
            ]),
        ]

    def scan_response(self) -> AdvertisingData:
        return AdvertisingData([
            (AdvertisingData.COMPLETE_LIST_OF_128_BIT_SERVICE_CLASS_UUIDS, bytes(UART_SERVICE)),
        ])

    def behave(self) -> None:
        echoes = self.lines.pipe(
            ops.do_action(lambda line: self.log.info("%s: received %r", self.name, line)),
            ops.map(lambda line: line.upper()),
        )
        ticks = rx.interval(5.0).pipe(ops.map(lambda count: f"tick {count + 1}".encode()))
        self.run(rx.merge(echoes, ticks), lambda text: self.notify(self.tx, text[:NOTIFICATION_BYTES]))

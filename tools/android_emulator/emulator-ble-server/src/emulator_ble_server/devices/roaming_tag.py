"""Roaming Tag: a Find Me key tag that leaves range and comes back."""

import reactivex as rx
from bumble.core import AdvertisingData
from bumble.gatt import Characteristic, CharacteristicValue, Service
from reactivex import operators as ops
from reactivex.subject import Subject

from ..peripheral import Peripheral
from ..signals import Roaming, Signal
from ..values import uuid16

#: Immediate Alert's Alert Level.
ALERT_LEVELS = {0: "no alert", 1: "mild alert", 2: "high alert"}


class RoamingTag(Peripheral):
    """Find Me (Immediate Alert) and Battery, on a tag that wanders off.

    - About 30 seconds in range, fading out towards the edge, then about 15
      out of range, gone from netsim: a connected central's link times out
      (supervision timeout, HCI 0x08) and its scan stops finding the tag
      until it is back.
    - Alert Level (write without response): 0, 1 or 2; the tag "beeps" for
      a high alert until told 0.
    - Battery Level (read, notify): a percent less every minute.
    """

    slug = "roaming-tag"

    def __init__(self, address: str, signal: Signal | None = None) -> None:
        super().__init__("Roaming Tag", address, signal or Roaming(-62, present=30, absent=15))
        self.alerts: Subject[int] = Subject()
        self.battery = Characteristic(
            uuid16(0x2A19), Characteristic.Properties.READ | Characteristic.Properties.NOTIFY,
            Characteristic.READABLE, bytes([93]),
        )

    def services(self) -> list[Service]:
        return [
            Service(uuid16(0x1802), [
                Characteristic(
                    uuid16(0x2A06), Characteristic.Properties.WRITE_WITHOUT_RESPONSE, Characteristic.WRITEABLE,
                    CharacteristicValue(write=lambda connection, value: self.alerts.on_next(bytes(value)[0] if value else 0)),
                ),
            ]),
            Service(uuid16(0x180F), [self.battery]),
        ]

    def advertisement(self) -> AdvertisingData:
        return AdvertisingData([
            (AdvertisingData.FLAGS, bytes([0x06])),
            (AdvertisingData.COMPLETE_LOCAL_NAME, self.name.encode()),
            (AdvertisingData.INCOMPLETE_LIST_OF_16_BIT_SERVICE_CLASS_UUIDS, bytes([0x02, 0x18])),
            # Tag.
            (AdvertisingData.APPEARANCE, (0x0200).to_bytes(2, "little")),
        ])

    def behave(self) -> None:
        # While the level is high, a beep a second; a new level replaces it.
        beeping = self.alerts.pipe(
            ops.do_action(lambda level: self.log.info("%s: %s", self.name, ALERT_LEVELS.get(level, f"alert {level}"))),
            ops.map(lambda level: rx.interval(1.0) if level == 2 else rx.empty()),
            ops.switch_latest(),
        )
        self.run(beeping, lambda _: self.log.info("%s: beep", self.name))
        self.run(
            rx.interval(60.0).pipe(ops.scan(lambda level, _: max(1, level - 1), 93)),
            lambda level: self.notify(self.battery, bytes([level])),
        )

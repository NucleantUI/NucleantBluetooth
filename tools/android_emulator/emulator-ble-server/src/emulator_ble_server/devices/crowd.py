"""The crowd: everyday devices that only advertise, so a scan has a full
list to show, sort and filter, with signals that do all sorts."""

import random

import reactivex as rx
from bumble.core import AdvertisingData

from ..peripheral import Peripheral
from ..signals import Drifting, Orbiting, Roaming, Signal, Steady
from ..values import manufacturer_data

#: Company identifiers from the Bluetooth SIG's assigned numbers, which
#: PureSwift's metadata names.
COMPANIES = [0x004C, 0x0006, 0x00E0, 0x0075, 0x0087, 0x0059, 0x009E, 0x006B]

NAMES = [
    "Kettle", "Desk Lamp", "Bathroom Scale", "Toothbrush", "Plant Sensor", "Speaker",
    "Bike Computer", "Fridge", "Smart Lock", "Key Finder", "Thermostat", "Air Purifier",
    "Coffee Maker", "Door Sensor", "Headphones", "Fitness Band",
]


class CrowdMember(Peripheral):
    """A device that advertises a name (or none), a company's manufacturer
    data whose last byte changes every few seconds, and its transmit power.
    Some take connections, with nothing to discover."""

    slug = "crowd"

    def __init__(
        self,
        name: str | None,
        address: str,
        signal: Signal,
        company: int,
        connectable: bool,
        tx_power: int,
        period: float,
    ) -> None:
        super().__init__(name or f"Unnamed {address[-5:]}", address, signal)
        self.advertised_name = name
        self.company = company
        self.connectable = connectable
        self.tx_power = tx_power
        self.period = period
        self.sequence = 0

    def advertisement(self) -> AdvertisingData:
        fields = [(AdvertisingData.FLAGS, bytes([0x06]))]
        if self.advertised_name:
            fields.append((AdvertisingData.COMPLETE_LOCAL_NAME, self.advertised_name.encode()))
        fields += [
            (AdvertisingData.MANUFACTURER_SPECIFIC_DATA, manufacturer_data(self.company, bytes([0xC0, self.sequence]))),
            (AdvertisingData.TX_POWER_LEVEL, self.tx_power.to_bytes(1, "little", signed=True)),
        ]
        return AdvertisingData(fields)

    def behave(self) -> None:
        self.run(rx.interval(self.period), self._next_sequence)

    def _next_sequence(self, _) -> None:
        self.sequence = (self.sequence + 1) & 0xFF
        self.readvertise()


class Crowd:
    """`count` crowd members, the same ones on every run: every fourth has
    no name, every third takes no connections, and their signals take turns
    being steady, drifting, orbiting and roaming."""

    def __init__(self, count: int, seed: int = 7) -> None:
        self.count = count
        self.random = random.Random(seed)

    def members(self, first_address: int) -> list[CrowdMember]:
        members = []
        for index in range(self.count):
            name = NAMES[index % len(NAMES)]
            if index >= len(NAMES):
                name += f" {index // len(NAMES) + 1}"
            members.append(CrowdMember(
                name=None if index % 4 == 3 else name,
                address=device_address(first_address + index),
                signal=self._signal(index),
                company=COMPANIES[index % len(COMPANIES)],
                connectable=index % 3 != 2,
                tx_power=self.random.choice([-20, -12, -8, -4, 0, 4]),
                period=self.random.uniform(3.0, 9.0),
            ))
        return members

    def _signal(self, index: int) -> Signal:
        seed = self.random.randrange(1 << 30)
        rssi = self.random.randint(-85, -45)
        match index % 4:
            case 0:
                return Steady(rssi, jitter=self.random.choice([0.5, 1, 2, 3]), seed=seed)
            case 1:
                return Drifting(weakest=rssi - 20, strongest=min(-35, rssi + 15), step=self.random.uniform(2, 7), seed=seed)
            case 2:
                return Orbiting(far=rssi - 15, near=min(-35, rssi + 15), period=self.random.uniform(20, 90), phase=self.random.random())
            case _:
                return Roaming(rssi, present=self.random.uniform(15, 45), absent=self.random.uniform(8, 25), seed=seed)


def device_address(number: int) -> str:
    """A random static address of this server's, `F0:4E:55:00:nn:nn`
    ("NU")."""
    return f"F0:4E:55:00:{number >> 8 & 0xFF:02X}:{number & 0xFF:02X}"

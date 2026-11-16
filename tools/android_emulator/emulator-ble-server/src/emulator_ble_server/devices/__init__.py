"""The fake devices, by the name the command line knows them by."""

from ..peripheral import Peripheral
from .beacons import Eddystone, IBeacon
from .blinky import BlinkyTag
from .crowd import Crowd, CrowdMember, device_address
from .dropout import Dropout
from .heart_rate import HeartRateMonitor
from .roaming_tag import RoamingTag
from .test_bench import TestBench
from .thermometer import Thermometer
from .uart import UartConsole
from .weather_station import WeatherStation

DEVICES: dict[str, type[Peripheral]] = {
    device.slug: device
    for device in (
        HeartRateMonitor,
        Thermometer,
        WeatherStation,
        UartConsole,
        TestBench,
        Dropout,
        RoamingTag,
        BlinkyTag,
        IBeacon,
        Eddystone,
    )
}

__all__ = ["DEVICES", "Crowd", "CrowdMember", "device_address"]

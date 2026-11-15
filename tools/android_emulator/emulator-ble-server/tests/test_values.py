"""The bytes the fake devices send, against the layouts in the specifications."""

import struct
import uuid

import pytest

from emulator_ble_server.netsim import Netsim
from emulator_ble_server.values import (
    custom_uuid,
    eddystone_tlm,
    eddystone_url,
    heart_rate_measurement,
    ibeacon,
    ieee11073_float,
    manufacturer_data,
)


def test_ieee11073_float_is_mantissa_under_exponent():
    # 36.62 = 3662 × 10^-2: exponent 0xFE, mantissa 0x000E4E, little-endian.
    assert ieee11073_float(36.62) == bytes([0x4E, 0x0E, 0x00, 0xFE])
    assert ieee11073_float(-1.5, exponent=-1) == struct.pack("<I", (0xFF << 24) | (-15 & 0xFFFFFF))


def test_ieee11073_float_refuses_what_does_not_fit():
    with pytest.raises(ValueError):
        ieee11073_float(1e6)


def test_heart_rate_measurement():
    assert heart_rate_measurement(72) == bytes([0x06, 72])
    assert heart_rate_measurement(72, 300) == bytes([0x0E, 72]) + struct.pack("<H", 300)
    # Over 255 the rate takes 16 bits, flagged in bit 0.
    assert heart_rate_measurement(300) == bytes([0x07]) + struct.pack("<H", 300)


def test_eddystone_url_encodes_scheme_and_endings():
    assert eddystone_url("https://github.com/NucleantUI", tx_power=-20) == (
        bytes([0x10, 0xEC, 0x03]) + b"github" + bytes([0x00]) + b"NucleantUI"
    )
    # The longest scheme wins.
    assert eddystone_url("https://www.example.org")[2:] == bytes([0x01]) + b"example" + bytes([0x08])


def test_eddystone_url_limits():
    with pytest.raises(ValueError):
        eddystone_url("ftp://example.com")
    with pytest.raises(ValueError):
        eddystone_url("https://a-very-long-host-name.example.com/path")


def test_eddystone_tlm_layout():
    frame = eddystone_tlm(battery_mv=3000, temperature=22.5, advertisements=7, uptime_s=12.3)
    assert frame == struct.pack(">BBHHII", 0x20, 0, 3000, 0x1680, 7, 123)


def test_ibeacon_layout():
    proximity = uuid.UUID("E2C56DB5-DFFB-48D2-B060-D0F5A71096E0")
    data = ibeacon(proximity, major=1, minor=2)
    assert data[:2] == bytes([0x02, 0x15])
    assert data[2:18] == proximity.bytes
    assert data[18:] == bytes([0x00, 0x01, 0x00, 0x02, 0xC5])


def test_manufacturer_data_starts_with_the_company_little_endian():
    assert manufacturer_data(0x004C, b"\x01") == bytes([0x4C, 0x00, 0x01])


def test_custom_uuids_differ_by_device_and_number():
    assert str(custom_uuid(0xAB, 1)).upper().startswith("7E5700AB-0001")
    assert custom_uuid(0xAB, 1) != custom_uuid(0xAB, 2) != custom_uuid(0xB1, 2)


@pytest.mark.parametrize(("rssi", "tx_power"), [(-86, -127), (-60, -101), (0, -41), (-20, -61), (-100, -127), (50, -21)])
def test_tx_power_for_rssi(rssi: int, tx_power: int):
    assert Netsim.tx_power_for(rssi) == tx_power

"""The bytes the fake devices send: GATT values and beacon frames, as the
specifications lay them out."""

import struct
import uuid

from bumble.core import UUID


def uuid16(value: int) -> UUID:
    """An assigned number's UUID (`0x180D` → Heart Rate)."""
    return UUID.from_16_bits(value)


def custom_uuid(device: int, number: int) -> UUID:
    """A 128-bit UUID of this server's own, for a device's service (`number`
    0) and characteristics: `7E57dddd-nnnn-4000-8000-4E55434C4541`."""
    return UUID(f"7E57{device:04X}-{number:04X}-4000-8000-4E55434C4541")


def ieee11073_float(value: float, exponent: int = -2) -> bytes:
    """IEEE-11073 32-bit FLOAT: a 24-bit mantissa under an 8-bit base-10
    exponent, little-endian (Health Thermometer's Temperature Measurement)."""
    mantissa = round(value / 10**exponent)
    if not -(2**23) <= mantissa < 2**23:
        raise ValueError(f"{value} does not fit a 24-bit mantissa at 10^{exponent}")
    return struct.pack("<I", ((exponent & 0xFF) << 24) | (mantissa & 0xFFFFFF))


def heart_rate_measurement(bpm: int, energy_kj: int | None = None) -> bytes:
    """Heart Rate Measurement: flags, an 8-bit rate (16-bit above 255), the
    sensor in contact, and the energy expended when given."""
    flags = 0x06  # sensor contact supported and detected
    rate = struct.pack("<B", bpm) if bpm <= 0xFF else struct.pack("<H", bpm)
    if bpm > 0xFF:
        flags |= 0x01
    energy = b""
    if energy_kj is not None:
        flags |= 0x08
        energy = struct.pack("<H", min(energy_kj, 0xFFFF))
    return bytes([flags]) + rate + energy


# Eddystone-URL's prefixes and the expansions it encodes as one byte.
_URL_SCHEMES = ["http://www.", "https://www.", "http://", "https://"]
_URL_EXPANSIONS = [
    ".com/", ".org/", ".edu/", ".net/", ".info/", ".biz/", ".gov/",
    ".com", ".org", ".edu", ".net", ".info", ".biz", ".gov",
]


def eddystone_url(url: str, tx_power: int = -20) -> bytes:
    """An Eddystone-URL frame: 0x10, the power at 0 m, then the URL with its
    scheme and common endings as one byte each."""
    # The longest scheme that matches: "https://www." before "https://".
    schemes = [(code, scheme) for code, scheme in enumerate(_URL_SCHEMES) if url.startswith(scheme)]
    if not schemes:
        raise ValueError(f"{url}: Eddystone-URL takes http:// or https:// URLs")
    code, scheme = max(schemes, key=lambda match: len(match[1]))
    rest = url[len(scheme):]
    encoded = bytearray([0x10, tx_power & 0xFF, code])
    while rest:
        for expansion_code, expansion in enumerate(_URL_EXPANSIONS):
            if rest.startswith(expansion):
                encoded.append(expansion_code)
                rest = rest[len(expansion):]
                break
        else:
            encoded += rest[0].encode("ascii")
            rest = rest[1:]
    if len(encoded) > 20:
        raise ValueError(f"{url} encodes to {len(encoded)} bytes; an Eddystone-URL frame holds 20")
    return bytes(encoded)


def eddystone_tlm(battery_mv: int, temperature: float, advertisements: int, uptime_s: float) -> bytes:
    """An Eddystone-TLM frame (unencrypted): battery voltage, temperature in
    8.8 fixed point, advertisements sent, and uptime in tenths of a second,
    big-endian."""
    temperature_88 = round(temperature * 256) & 0xFFFF
    return struct.pack(">BBHHII", 0x20, 0x00, battery_mv, temperature_88, advertisements, round(uptime_s * 10))


def ibeacon(proximity_uuid: uuid.UUID, major: int, minor: int, measured_power: int = -59) -> bytes:
    """iBeacon's manufacturer data after the company identifier: type 0x02,
    length 0x15, the proximity UUID, major and minor (big-endian), and the
    power measured at 1 m."""
    return bytes([0x02, 0x15]) + proximity_uuid.bytes + struct.pack(">HHb", major, minor, measured_power)


def manufacturer_data(company: int, payload: bytes) -> bytes:
    """Manufacturer Specific Data: the company identifier, little-endian,
    then the company's own bytes."""
    return struct.pack("<H", company) + payload

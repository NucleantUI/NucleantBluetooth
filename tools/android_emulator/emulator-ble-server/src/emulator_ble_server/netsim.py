"""netsim, the Android emulator's virtual Bluetooth radio, and a Bumble
controller on it for each fake device."""

import asyncio
import logging
import os
import pathlib

import grpc
from bumble.device import Device
from bumble.hci import Address
from bumble.transport.android_netsim import open_android_netsim_host_transport_with_channel
from bumble.transport.common import Transport

log = logging.getLogger(__name__)


class NetsimNotFound(Exception):
    pass


class Netsim:
    """The netsimd an emulator started, found by its gRPC port.

    Each device gets a controller of its own over a gRPC connection of its
    own. netsim sometimes leaves a new controller hanging before it answers
    at all; a bring-up that takes longer than `timeout` seconds is dropped
    and tried again on a new connection.
    """

    def __init__(self, port: int | None = None, attempts: int = 10, timeout: float = 8.0) -> None:
        self.port = port if port is not None else self.find_port()
        self.attempts = attempts
        self.timeout = timeout

    @staticmethod
    def find_port() -> int:
        """netsimd writes `netsim.ini` (`grpc.port=…`) into the TMPDIR of
        whatever started the emulator. On macOS an emulator started from
        another app (Android Studio, a launcher) has a TMPDIR of its own
        below the same temporary root, so the folders under TMPDIR are
        searched too, and the newest file wins."""
        tmpdir = pathlib.Path(os.environ.get("TMPDIR", "/tmp"))
        candidates = [tmpdir / "netsim.ini", *tmpdir.glob("*/netsim.ini")]
        found = [path for path in candidates if path.is_file()]
        if not found:
            raise NetsimNotFound(f"no netsim.ini under {tmpdir}: start the emulator first, or pass --netsim-port")
        newest = max(found, key=lambda path: path.stat().st_mtime)
        for line in newest.read_text().splitlines():
            key, _, value = line.partition("=")
            if key.strip() == "grpc.port":
                return int(value)
        raise NetsimNotFound(f"{newest} has no grpc.port")

    #: What netsim adds to an advertiser's transmit power to get the RSSI a
    #: scanner sees, every device sitting at the same spot (measured: TX
    #: -127 dBm reads -86, TX -40 reads 0). It holds up to an RSSI of +20,
    #: where netsim stops; TX 0 reads -8, outside the line.
    PATH_GAIN = 41
    #: The transmit powers that stay on that line.
    TX_POWER_RANGE = range(-127, -20)

    @classmethod
    def tx_power_for(cls, rssi: int) -> int:
        """The transmit power that makes netsim report `rssi` (-86 to +20
        dBm; outside that, the nearest it can)."""
        return max(cls.TX_POWER_RANGE.start, min(cls.TX_POWER_RANGE.stop - 1, rssi - cls.PATH_GAIN))

    async def device(self, name: str, address: str, chip: str) -> tuple[Device, Transport]:
        """A powered-on Bumble device named `name` at `address`, on a new
        netsim controller called `chip`.

        netsim turns a device away for a few seconds after the same device
        left (the connection is reset), and now and then leaves a new
        controller hanging; both are tried again, a little later each time.
        """
        for attempt in range(1, self.attempts + 1):
            bring_up = asyncio.ensure_future(self._bring_up(name, address, f"{chip}-{attempt}"))
            done, _ = await asyncio.wait([bring_up], timeout=self.timeout)
            if not done:
                bring_up.cancel()
                log.debug("%s: netsim did not answer (attempt %d)", name, attempt)
            elif bring_up.exception() is None:
                return bring_up.result()
            else:
                log.debug("%s: netsim turned it away (attempt %d): %s", name, attempt, bring_up.exception())
                await asyncio.sleep(0.5 * attempt)
        raise TimeoutError(f"{name}: netsim gave no controller after {self.attempts} attempts")

    async def _bring_up(self, name: str, address: str, chip: str) -> tuple[Device, Transport]:
        # A local subchannel pool: a connection of its own, not one shared
        # with every other device's channel to the same port.
        channel = grpc.aio.insecure_channel(
            f"localhost:{self.port}",
            options=[("grpc.use_local_subchannel_pool", 1)],
        )
        try:
            transport = await open_android_netsim_host_transport_with_channel(channel, {"name": chip})
        except BaseException:
            await channel.close()
            raise
        device = Device.with_hci(name, Address(address), transport.source, transport.sink)
        try:
            await device.power_on()
        except BaseException:
            await transport.close()
            raise
        return device, transport

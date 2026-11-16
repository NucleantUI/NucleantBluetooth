"""emulator-ble-server: the command line."""

import argparse
import asyncio
import contextlib
import logging
import sys

from .devices import DEVICES, Crowd, device_address
from .netsim import Netsim, NetsimNotFound
from .peripheral import Peripheral
from .server import Server


def main() -> None:
    parser = argparse.ArgumentParser(
        prog="emulator-ble-server",
        description=(
            "Fake Bluetooth LE peripherals for the Android emulator: Bumble devices on netsim, "
            "the emulator's virtual radio, driven by reactivex timers."
        ),
    )
    parser.add_argument(
        "devices", nargs="*", metavar="DEVICE",
        help=f"the devices to run, all when none are named: {', '.join(DEVICES)}",
    )
    parser.add_argument(
        "--crowd", type=int, default=12, metavar="N",
        help="everyday devices that only advertise, to fill the scan (default 12, 0 for none)",
    )
    parser.add_argument("--netsim-port", type=int, metavar="PORT", help="netsimd's gRPC port (default: from its netsim.ini)")
    parser.add_argument("--list", action="store_true", help="list the devices and what they do, then exit")
    parser.add_argument(
        "-v", "--verbose", action="count", default=0,
        help="-v: every device event; -vv: Bumble's HCI traffic too",
    )
    arguments = parser.parse_args()

    if arguments.list:
        for slug, device in DEVICES.items():
            summary = " ".join((device.__doc__ or "").split("\n\n")[0].split())
            print(f"{slug}\n    {summary}\n    Signal: {device(device_address(0)).signal.describe()}.")
        print("crowd\n    Everyday devices that only advertise (--crowd N), signals steady, drifting, orbiting and roaming.")
        return

    unknown = [name for name in arguments.devices if name not in DEVICES]
    if unknown:
        parser.error(f"no device {', '.join(unknown)}; there are {', '.join(DEVICES)}")

    logging.basicConfig(format="%(asctime)s %(message)s", datefmt="%H:%M:%S", level=logging.WARNING)
    logging.getLogger("emulator_ble_server").setLevel(logging.DEBUG if arguments.verbose else logging.INFO)
    if arguments.verbose > 1:
        logging.getLogger("bumble").setLevel(logging.DEBUG)

    try:
        netsim = Netsim(arguments.netsim_port)
    except NetsimNotFound as error:
        sys.exit(f"emulator-ble-server: {error}")

    peripherals: list[Peripheral] = [
        DEVICES[slug](device_address(number + 1))
        for number, slug in enumerate(arguments.devices or DEVICES)
    ]
    peripherals += Crowd(arguments.crowd).members(first_address=0x100)

    with contextlib.suppress(KeyboardInterrupt):
        asyncio.run(Server(peripherals, netsim).run())

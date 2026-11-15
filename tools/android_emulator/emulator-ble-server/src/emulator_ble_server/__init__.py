"""Fake Bluetooth LE peripherals for the Android emulator: Bumble devices on
netsim, the emulator's virtual radio, driven by reactivex timers."""

import os

# gRPC's own INFO lines (connections netsim lets go of, fork notices) drown
# the devices' log; set before gRPC loads, unless asked for.
os.environ.setdefault("GRPC_VERBOSITY", "ERROR")

from .cli import main  # noqa: E402

__all__ = ["main"]

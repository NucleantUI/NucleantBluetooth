"""The server: every fake device on one event loop and one reactivex
scheduler."""

import asyncio
import logging

from reactivex.scheduler.eventloop import AsyncIOScheduler

from .netsim import Netsim
from .peripheral import Peripheral

log = logging.getLogger(__name__)


class Server:
    """Brings the devices up on netsim, a few at a time, and keeps them
    running until it is stopped (Ctrl-C)."""

    def __init__(self, peripherals: list[Peripheral], netsim: Netsim, at_once: int = 4) -> None:
        self.peripherals = peripherals
        self.netsim = netsim
        self.at_once = asyncio.Semaphore(at_once)
        self.running: list[Peripheral] = []

    async def run(self) -> None:
        scheduler = AsyncIOScheduler(asyncio.get_running_loop())
        log.info("netsim on port %d; bringing up %d devices", self.netsim.port, len(self.peripherals))
        try:
            await asyncio.gather(*(self._start(peripheral, scheduler) for peripheral in self.peripherals))
            log.info("%d of %d devices up. Ctrl-C to stop.", len(self.running), len(self.peripherals))
            await asyncio.Event().wait()
        finally:
            await asyncio.gather(*(peripheral.stop() for peripheral in self.running), return_exceptions=True)

    async def _start(self, peripheral: Peripheral, scheduler: AsyncIOScheduler) -> None:
        async with self.at_once:
            try:
                await peripheral.start(self.netsim, scheduler)
            except TimeoutError as error:
                log.error("%s", error)
                return
        self.running.append(peripheral)

"""A fake Bluetooth LE peripheral: a Bumble device on its own netsim
controller, its GATT services, what it advertises, how strong its signal is,
and the reactivex streams that make it do things over time."""

import asyncio
import logging
from collections.abc import Callable, Coroutine
from typing import Any

from bumble.core import AdvertisingData, CommandTimeoutError
from bumble.device import (
    AdvertisingEventProperties,
    AdvertisingParameters,
    AdvertisingSet,
    Connection,
    Device,
)
from bumble.gatt import Characteristic, Service
from bumble.hci import OwnAddressType
from bumble.transport.common import Transport
from reactivex import Observable
from reactivex import operators as ops
from reactivex.abc import DisposableBase, SchedulerBase
from reactivex.disposable import CompositeDisposable
from reactivex.subject import Subject

from .netsim import Netsim
from .signals import Signal

#: The smallest change in signal, in dB, that changes the transmit power.
SIGNAL_STEP = 2


class Peripheral:
    """One fake device.

    A subclass says what it is (`services`, `advertisement`,
    `scan_response`), what it does (`behave`, reactivex streams this class
    keeps and disposes of when it stops), and how its signal behaves (the
    `Signal` it is given). Values change through `notify` and `indicate`,
    which also make them what a read returns. `connections` emits each
    connection a central makes and `disconnections` each that ends, for
    streams that last as long as one connection.

    While its signal says it is out of range the device is not on netsim at
    all: a central's scan stops finding it, and a connection to it times
    out. Back in range it comes back with the same address, services and
    advertisement.
    """

    #: Name on the command line.
    slug = "peripheral"
    #: Whether centrals can connect. A device that can't advertises
    #: non-connectable and non-scannable, without a scan response.
    connectable = True
    #: Milliseconds between advertisements.
    advertising_interval = 1000.0

    def __init__(self, name: str, address: str, signal: Signal) -> None:
        self.name = name
        self.address = address
        self.signal = signal
        self.log = logging.getLogger(f"emulator_ble_server.{self.slug}")
        self.netsim: Netsim | None = None
        self.scheduler: SchedulerBase | None = None
        self.device: Device | None = None
        self.transport: Transport | None = None
        self.advertising_set: AdvertisingSet | None = None
        self.quiet = False
        self.rssi: int | None = signal.rssi
        #: The signal's latest reading, and whether a task is following it.
        self._wanted_rssi: int | None = signal.rssi
        self._following = False
        self._appearances = 0
        #: The RSSI the advertising set's transmit power is set for.
        self._advertised_rssi: int | None = None
        self.subscriptions = CompositeDisposable()
        self.connections: Subject[Connection] = Subject()
        self.disconnections: Subject[Connection] = Subject()
        self._tasks: set[asyncio.Task[Any]] = set()
        self._radio = asyncio.Lock()

    # MARK: What a device is

    def services(self) -> list[Service]:
        return []

    def advertisement(self) -> AdvertisingData:
        return AdvertisingData([
            (AdvertisingData.FLAGS, bytes([0x06])),
            (AdvertisingData.COMPLETE_LOCAL_NAME, self.name.encode()),
        ])

    def scan_response(self) -> AdvertisingData | None:
        return None

    def behave(self) -> None:
        """Start the device's streams, with `run` or `keep` for each."""

    @property
    def chip(self) -> str:
        """Its controller's name in netsim: the slug and the end of its
        address, so the crowd's members differ."""
        return f"{self.slug}-{self.address[-5:].replace(':', '')}"

    @property
    def in_range(self) -> bool:
        return self.device is not None

    # MARK: Lifecycle

    async def start(self, netsim: Netsim, scheduler: SchedulerBase) -> None:
        self.netsim = netsim
        self.scheduler = scheduler
        await self._radio_work(self._appear)
        if not self.in_range:
            raise TimeoutError(f"{self.name}: netsim gave no controller")
        self.behave()
        self.run(self.signal.readings().pipe(ops.distinct_until_changed()), self._signal_changed)
        self.log.info("%s: up at %s, signal %s", self.name, self.address, self.signal.describe())

    async def stop(self) -> None:
        self.subscriptions.dispose()
        for task in list(self._tasks):
            task.cancel()
        async with self._radio:
            await self._vanish()

    async def _appear(self) -> None:
        """Onto netsim: a controller, the services, the advertising set."""
        assert self.netsim
        # A new name for each appearance: netsim may still be letting go
        # of the last one.
        self._appearances += 1
        device, self.transport = await self.netsim.device(
            self.name, self.address, chip=f"{self.chip}-{self._appearances}",
        )
        device.add_services(self.services())
        device.on("connection", self._connected)
        self.device = device
        self.advertising_set = await device.create_advertising_set(
            advertising_parameters=self._advertising_parameters(),
            advertising_data=bytes(self.advertisement()),
            scan_response_data=self._scan_response_bytes(),
            auto_start=not self.quiet,
            # Advertising again once a central disconnects.
            auto_restart=self.connectable,
        )
        self._advertised_rssi = self.rssi

    async def _vanish(self) -> None:
        """Off netsim: the controller goes, and with it every connection."""
        transport, self.transport = self.transport, None
        self.device = None
        self.advertising_set = None
        if transport:
            await transport.close()

    def _connected(self, connection: Connection) -> None:
        self.log.info("%s: connected to %s", self.name, connection.peer_address)

        def disconnected(reason: int) -> None:
            self.log.info("%s: %s went away (reason 0x%02X)", self.name, connection.peer_address, reason)
            self.disconnections.on_next(connection)

        connection.on("disconnection", disconnected)
        self.connections.on_next(connection)

    # MARK: Signal

    def _signal_changed(self, rssi: int | None) -> None:
        # One task follows the signal; readings that come while it is busy
        # (coming back into range takes a while) leave only the latest.
        self._wanted_rssi = rssi
        if not self._following:
            self._following = True
            self.spawn(self._follow_signal())

    async def _follow_signal(self) -> None:
        try:
            while True:
                rssi = self._wanted_rssi
                await self._radio_work(lambda: self._take_signal(rssi))
                if self._wanted_rssi == rssi:
                    return
        finally:
            self._following = False

    async def _take_signal(self, rssi: int | None) -> None:
        self.rssi = rssi
        if rssi is None:
            if self.in_range:
                await self._vanish()
                self.log.info("%s: out of range", self.name)
        elif not self.in_range:
            try:
                await self._appear()
            except TimeoutError as error:
                self.log.warning("%s", error)
                return
            self.log.info("%s: back in range at %d dBm", self.name, rssi)
        elif self._advertised_rssi is None or abs(rssi - self._advertised_rssi) >= SIGNAL_STEP:
            # Smaller changes wait: each one restarts the advertising set,
            # and netsim chokes on too many.
            self.log.debug("%s: %d dBm", self.name, rssi)
            await self._retune()

    def _advertising_parameters(self) -> AdvertisingParameters:
        assert self.netsim
        tx_power = self.netsim.tx_power_for(self.rssi if self.rssi is not None else self.signal.rssi)
        return AdvertisingParameters(
            advertising_event_properties=AdvertisingEventProperties(
                is_connectable=self.connectable,
                is_scannable=self.connectable,
                is_legacy=True,
            ),
            own_address_type=OwnAddressType.RANDOM,
            # One unsigned byte on the wire.
            advertising_tx_power=tx_power & 0xFF,
            primary_advertising_interval_min=self.advertising_interval,
            primary_advertising_interval_max=self.advertising_interval,
        )

    # MARK: Advertising

    def readvertise(self) -> None:
        """Advertise what `advertisement` and `scan_response` say now."""
        self.spawn(self._radio_work(self._update_data))

    async def _update_data(self) -> None:
        """The advertising set's data, replaced while it runs: complete data
        may change while advertising is on."""
        advertising = self.advertising_set
        if advertising is None:
            return
        await advertising.set_advertising_data(bytes(self.advertisement()))
        if self.connectable:
            await advertising.set_scan_response_data(self._scan_response_bytes())

    async def _retune(self) -> None:
        """The transmit power the signal asks for. Parameters change only
        while the set is stopped, so it stops and starts around them, unless
        it should be quiet or a central is connected (it starts again by
        itself when the central goes)."""
        advertising, device = self.advertising_set, self.device
        if advertising is None or device is None:
            return
        if advertising.enabled:
            await advertising.stop()
        await advertising.set_advertising_parameters(self._advertising_parameters())
        self._advertised_rssi = self.rssi
        if not self.quiet and not (self.connectable and device.connections):
            await advertising.start()

    async def go_quiet(self, quiet: bool) -> None:
        """Stop advertising (still connectable while connected), or start
        again."""

        async def switch() -> None:
            self.quiet = quiet
            advertising, device = self.advertising_set, self.device
            if advertising is None or device is None:
                return
            if quiet and advertising.enabled:
                await advertising.stop()
            elif not quiet and not advertising.enabled and not (self.connectable and device.connections):
                await advertising.start()

        await self._radio_work(switch)

    async def _radio_work(self, work: Callable[[], Coroutine[Any, Any, None]]) -> None:
        """`work` on the radio, one thing at a time. A controller that stops
        answering (netsim drops one now and then under load) leaves netsim
        and joins it again."""
        async with self._radio:
            try:
                await work()
            except CommandTimeoutError:
                if not self.in_range:
                    return
                self.log.warning("%s: controller stopped answering; joining netsim again", self.name)
                await self._vanish()
                try:
                    await self._appear()
                except TimeoutError as error:
                    self.log.warning("%s", error)

    def _scan_response_bytes(self) -> bytes:
        scan_response = self.scan_response() if self.connectable else None
        return bytes(scan_response) if scan_response else b""

    # MARK: Values

    def notify(self, characteristic: Characteristic, value: bytes) -> None:
        characteristic.value = value
        if self.device:
            self.spawn(self.device.notify_subscribers(characteristic, value))

    def indicate(self, characteristic: Characteristic, value: bytes) -> None:
        characteristic.value = value
        if self.device:
            self.spawn(self.device.indicate_subscribers(characteristic, value))

    # MARK: Streams

    def keep(self, subscription: DisposableBase) -> None:
        """Dispose of `subscription` when the device stops."""
        self.subscriptions.add(subscription)

    def run(self, stream: Observable[Any], on_next: Callable[[Any], None]) -> None:
        """Subscribe `on_next` to `stream` on the event loop, for as long as
        the device runs. An error in the stream is logged, not raised."""
        self.keep(stream.subscribe(
            on_next=on_next,
            on_error=lambda error: self.log.error("%s: stream failed: %r", self.name, error),
            scheduler=self.scheduler,
        ))

    def until_disconnected(self, connection: Connection):
        """An operator that ends a stream when `connection` does."""
        return ops.take_until(self.disconnections.pipe(ops.filter(lambda ended: ended is connection)))

    def spawn(self, coroutine: Coroutine[Any, Any, Any]) -> None:
        task = asyncio.ensure_future(coroutine)
        self._tasks.add(task)
        task.add_done_callback(self._finished)

    def _finished(self, task: asyncio.Task[Any]) -> None:
        self._tasks.discard(task)
        if not task.cancelled() and task.exception():
            self.log.warning("%s: %r", self.name, task.exception())

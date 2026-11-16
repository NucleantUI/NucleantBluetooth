"""How strong a device's signal is at the scanner, over time.

Each kind is a class whose `readings()` is a reactivex stream of RSSI in dBm,
`None` while the device is out of range. A device takes one and leaves
the rest to it: the device sets its transmit power so that netsim reports
that RSSI, and leaves netsim while the stream says it is out of range.
"""

import math
import random

import reactivex as rx
from reactivex import Observable
from reactivex import operators as ops

#: Around here a device is too far to hear.
RANGE_EDGE = -95


class Signal:
    """A signal that stays as it is."""

    def __init__(self, rssi: int = -60) -> None:
        self.rssi = rssi

    def readings(self) -> Observable[int | None]:
        return rx.of(self.rssi)

    def describe(self) -> str:
        return f"steady at {self.rssi} dBm"


class Steady(Signal):
    """Something that stays where it is: `rssi`, give or take `jitter` dB
    every `period` seconds, the way a still device's signal flickers."""

    def __init__(self, rssi: int, jitter: float = 2.0, period: float = 2.0, seed: int | None = None) -> None:
        super().__init__(rssi)
        self.jitter = jitter
        self.period = period
        self.random = random.Random(seed)

    def readings(self) -> Observable[int | None]:
        return rx.interval(self.period).pipe(
            ops.map(lambda _: round(self.rssi + self.random.uniform(-self.jitter, self.jitter))),
            ops.start_with(self.rssi),
        )

    def describe(self) -> str:
        return f"steady at {self.rssi} ± {self.jitter:g} dBm"


class Drifting(Signal):
    """Something carried around: a random walk between `weakest` and
    `strongest`, up to `step` dB every two seconds."""

    def __init__(self, weakest: int, strongest: int, step: float = 4.0, seed: int | None = None) -> None:
        super().__init__((weakest + strongest) // 2)
        self.weakest = weakest
        self.strongest = strongest
        self.step = step
        self.random = random.Random(seed)

    def readings(self) -> Observable[int | None]:
        return rx.interval(2.0).pipe(
            ops.scan(lambda rssi, _: self._walk(rssi), float(self.rssi)),
            ops.map(round),
            ops.start_with(self.rssi),
        )

    def _walk(self, rssi: float) -> float:
        return max(self.weakest, min(self.strongest, rssi + self.random.uniform(-self.step, self.step)))

    def describe(self) -> str:
        return f"drifting between {self.weakest} and {self.strongest} dBm"


class Orbiting(Signal):
    """Something moving round the room on a path: from `far` to `near` and
    back every `period` seconds."""

    def __init__(self, far: int, near: int, period: float = 40.0, phase: float = 0.0) -> None:
        super().__init__(far)
        self.far = far
        self.near = near
        self.period = period
        self.phase = phase

    def readings(self) -> Observable[int | None]:
        middle, swing = (self.far + self.near) / 2, (self.near - self.far) / 2
        return rx.interval(2.0).pipe(
            ops.map(lambda tick: round(middle + swing * math.sin(2 * math.pi * (tick * 2 / self.period + self.phase)))),
            ops.start_with(round(middle)),
        )

    def describe(self) -> str:
        return f"orbiting {self.far} to {self.near} dBm every {self.period:.0f} s"


class Roaming(Signal):
    """Something that leaves: in range for `present` seconds, drifting
    around `rssi`, weaker and weaker towards the edge, then out of range for
    `absent` seconds, then back. The times vary by a third each round."""

    def __init__(self, rssi: int, present: float = 30.0, absent: float = 15.0, seed: int | None = None) -> None:
        super().__init__(rssi)
        self.present = present
        self.absent = absent
        self.random = random.Random(seed)

    def readings(self) -> Observable[int | None]:
        return rx.defer(lambda _: self._visit()).pipe(ops.repeat())

    def _visit(self) -> Observable[int | None]:
        stay = max(4, round(self.present * self.random.uniform(0.67, 1.33)))
        away = max(4, round(self.absent * self.random.uniform(0.67, 1.33)))
        # The last quarter of the stay fades out to the edge.
        fade_from = stay * 3 // 4

        def strength(second: int) -> int:
            if second < fade_from:
                return round(self.rssi + self.random.uniform(-3, 3))
            fade = (second - fade_from + 1) / (stay - fade_from)
            return round(self.rssi + (RANGE_EDGE - self.rssi) * fade)

        here = rx.interval(1.0).pipe(ops.take(stay), ops.map(strength), ops.start_with(self.rssi))
        gone = rx.of(None).pipe(ops.concat(rx.timer(float(away)).pipe(ops.ignore_elements())))
        return rx.concat(here, gone)

    def describe(self) -> str:
        return f"roaming around {self.rssi} dBm, out of range about {self.absent:.0f} s of every {self.present + self.absent:.0f} s"

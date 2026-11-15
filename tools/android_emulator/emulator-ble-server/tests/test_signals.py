"""Signals, on reactivex's virtual-time scheduler: what each kind reports
over a few minutes, without waiting for them."""

from reactivex.testing import TestScheduler

from emulator_ble_server.signals import Drifting, Orbiting, Roaming, Steady

SECONDS = 180


def readings(signal, seconds: int = SECONDS) -> list[tuple[float, int | None]]:
    """(second, RSSI) for every reading in the first `seconds`."""
    scheduler = TestScheduler()
    seen: list[tuple[float, int | None]] = []
    signal.readings().subscribe(
        lambda rssi: seen.append((scheduler.clock, rssi)),
        scheduler=scheduler,
    )
    scheduler.advance_to(seconds)
    return seen


def strengths(signal) -> list[int]:
    """The readings while in range."""
    return [rssi for _, rssi in readings(signal) if rssi is not None]


def test_steady_stays_within_its_jitter():
    values = strengths(Steady(-60, jitter=2, seed=1))
    assert len(values) > 50
    assert all(-62 <= rssi <= -58 for rssi in values)


def test_drifting_stays_between_its_bounds_and_moves_a_lot():
    values = strengths(Drifting(weakest=-90, strongest=-50, step=5, seed=2))
    assert all(-90 <= rssi <= -50 for rssi in values)
    assert max(values) - min(values) >= 15


def test_orbiting_reaches_both_ends():
    values = strengths(Orbiting(far=-80, near=-40, period=40))
    assert min(values) <= -78
    assert max(values) >= -42


def test_roaming_leaves_and_comes_back():
    seen = readings(Roaming(-60, present=20, absent=10, seed=3))
    gaps = [second for second, rssi in seen if rssi is None]
    assert len(gaps) >= 3, "out of range at least three times in three minutes"
    # After each time out of range, it is back.
    for second in gaps[:-1]:
        assert any(later > second and rssi is not None for later, rssi in seen)
    # Before leaving it fades towards the edge.
    values = [rssi for _, rssi in seen if rssi is not None]
    assert min(values) <= -85

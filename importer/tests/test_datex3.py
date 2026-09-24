from datetime import UTC, datetime
from pathlib import Path

from homemaps_traffic import datex3

FIXTURES = Path(__file__).parent / "fixtures"


def test_measurement_sites():
    with open(FIXTURES / "measurement_sites.xml", "rb") as stream:
        sites = list(datex3.read_measurement_sites(stream))
    assert [site.key for site in sites] == ["SITE_A@27", "SITE_B@3"]
    assert sites[0].points == ((52.389347, 4.818521), (52.389328, 4.794803))
    # Two partial lines become one sequence of points, in order.
    assert len(sites[1].points) == 4


def test_travel_times_skip_unusable_measurements():
    with open(FIXTURES / "travel_times.xml", "rb") as stream:
        travel_times = {t.id: t for t in datex3.read_travel_times(stream)}
    # B: dataError, C: zero observations.
    assert set(travel_times) == {"SITE_A", "SITE_D"}
    assert travel_times["SITE_A"].seconds == 113.76
    assert travel_times["SITE_A"].normal_seconds == 60.0
    assert travel_times["SITE_D"].normal_seconds is None


def _closures(now):
    with open(FIXTURES / "closures.xml", "rb") as stream:
        return {closure.id: closure for closure in datex3.read_closures(stream, now)}


def test_closures_during_the_day():
    active = _closures(datetime(2026, 9, 21, 12, 0, tzinfo=UTC))
    # Not: VOORBIJ (ended), RIJSTROOK (no closure), NACHT (outside the
    # window), VRACHT (does not apply to cars).
    assert set(active) == {"ACTIEF"}
    assert len(active["ACTIEF"].points) == 3
    assert not active["ACTIEF"].whole_road


def test_closures_in_the_night_window():
    active = _closures(datetime(2026, 9, 21, 23, 0, tzinfo=UTC))
    assert set(active) == {"ACTIEF", "NACHT"}
    assert active["NACHT"].whole_road


def test_time_with_nanoseconds():
    assert datex3._time("2026-09-15T17:40:18.057252991Z") == datetime(
        2026, 9, 15, 17, 40, 18, 57252, tzinfo=UTC
    )


def test_measures_for_the_map():
    midday = datetime(2026, 9, 21, 12, 0, tzinfo=UTC)
    with open(FIXTURES / "closures.xml", "rb") as stream:
        measures = {m.id: m for m in datex3.read_measures(stream, midday)}
    # Also the lane and the truck closure: the map layer decides what happens to them.
    assert set(measures) == {"ACTIEF", "RIJSTROOK", "VRACHT"}
    assert measures["ACTIEF"].closes
    assert measures["ACTIEF"].end == datetime(2026, 11, 12, 15, 0, tzinfo=UTC)
    assert not measures["RIJSTROOK"].closes
    assert measures["VRACHT"].trucks_only and not measures["VRACHT"].closes


def test_incidents_accident_and_breakdown_valid_now():
    now = datetime(2026, 9, 22, 15, 0, tzinfo=UTC)
    with open(FIXTURES / "incidents.xml", "rb") as stream:
        incidents = {m.id: m for m in datex3.read_incidents(stream, now)}
    # VOORBIJ has ended; VERGETEN has not been updated for days. LANG has been
    # there for two days, but was just updated. ONZEKER is not confirmed.
    assert set(incidents) == {"ONGEVAL", "PECH", "LANG", "BEVESTIGD"}
    assert incidents["ONGEVAL"].kind == "accident"
    assert incidents["ONGEVAL"].point == (52.1, 5.1)
    assert incidents["ONGEVAL"].bearing == 141
    assert incidents["PECH"].kind == "breakdown"
    assert incidents["PECH"].bearing is None


def test_planned_closures_with_their_windows():
    start = datetime(2026, 9, 22, 12, 0, tzinfo=UTC)
    end = datetime(2026, 9, 30, 12, 0, tzinfo=UTC)
    with open(FIXTURES / "planning.xml", "rb") as stream:
        planned = {a.id: a for a in datex3.read_planned_closures(stream, start, end)}
    # VOLGEND_JAAR falls outside the week.
    assert set(planned) == {"NACHTEN", "WEEKEND"}
    # Of the three nights only the one in the week counts; the previous one is over.
    assert planned["NACHTEN"].windows == (
        (datetime(2026, 9, 23, 20, tzinfo=UTC), datetime(2026, 9, 24, 4, tzinfo=UTC)),
    )
    # Without validPeriods: one window from beginning to end.
    assert planned["WEEKEND"].windows == (
        (datetime(2026, 9, 26, 6, tzinfo=UTC), datetime(2026, 9, 27, 20, tzinfo=UTC)),
    )
    assert planned["WEEKEND"].whole_road


def _speed_limits(start, end):
    with open(FIXTURES / "speed_limits.xml", "rb") as stream:
        return {s.id: s for s in datex3.read_speed_limits(stream, start, end)}


def test_temporary_speed_limits_during_the_day():
    midday = datetime(2026, 9, 22, 12, 0, tzinfo=UTC)
    limits = _speed_limits(midday, midday)
    # Not: NACHT (only tonight), VRACHT (trucks only), ADVIES (not mandatory),
    # VOORBIJ (ended), GEEN_SNELHEID (a lane closure).
    assert set(limits) == {"WERK"}
    work = limits["WERK"]
    assert work.kph == 30
    assert work.key == "WERK@3"
    assert work.cause == "roadMaintenance"
    # Two partial lines: in order, and as one sequence of points to match.
    assert len(work.lines) == 2
    assert work.points[0] == (53.29151, 6.196199) and work.points[-1] == (53.29539, 6.19573)
    assert work.applies(midday)
    assert not work.applies(datetime(2026, 10, 10, tzinfo=UTC))


def test_temporary_speed_limits_lookahead_and_window():
    # With two hours of lookahead (like the planning feed): the night counts,
    # but only applies from eight o'clock.
    start = datetime(2026, 9, 22, 19, 0, tzinfo=UTC)
    limits = _speed_limits(start, datetime(2026, 9, 22, 21, 0, tzinfo=UTC))
    assert set(limits) == {"WERK", "NACHT"}
    night = limits["NACHT"]
    assert night.kph == 70
    assert not night.applies(start)
    assert night.applies(datetime(2026, 9, 22, 23, 0, tzinfo=UTC))


def test_open_bridges():
    now = datetime(2026, 9, 22, 20, 0, tzinfo=UTC)
    with open(FIXTURES / "current_situation.xml", "rb") as stream:
        bridges = {b.id: b for b in datex3.read_bridges(stream, now)}
    # Not: GEPLAND (not in progress yet), VOORBIJ (ended), GEEN_BRUG.
    assert set(bridges) == {"OPEN", "DICHTGAAN"}
    assert bridges["OPEN"].point == (53.07374, 5.335099)

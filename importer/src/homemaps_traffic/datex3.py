"""The NDW feeds (DATEX II v3) the importer uses, read as a stream.

The measurement site configuration is well over 100 MB unpacked; everything
therefore goes through iterparse and every handled element is released right away.
"""

import gzip
from collections.abc import Iterator
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import BinaryIO
from xml.etree.ElementTree import Element, iterparse

Point = tuple[float, float]  # (lat, lon)

XSI_TYPE = "{http://www.w3.org/2001/XMLSchema-instance}type"
CLOSURE_TYPES = {"carriagewayClosures", "roadClosed"}


def _name(element: Element) -> str:
    return element.tag.rsplit("}", 1)[-1]


def _find(element: Element, name: str) -> Iterator[Element]:
    return (child for child in element.iter() if _name(child) == name)


def _first(element: Element, name: str) -> Element | None:
    return next(_find(element, name), None)


def _points(poslist: str) -> list[Point]:
    numbers = [float(part) for part in poslist.split()]
    return list(zip(numbers[0::2], numbers[1::2], strict=True))


def _records(stream: BinaryIO, name: str) -> Iterator[Element]:
    """Yields every element `name` as soon as it is complete, and clears it afterwards."""
    root = None
    for event, element in iterparse(stream, events=("start", "end")):
        if event == "start":
            if root is None:
                root = element
            continue
        if _name(element) == name:
            yield element
            element.clear()
            # Otherwise the parent holds on to 67,000 empty shells.
            root.clear()


def open_feed(path_or_stream) -> BinaryIO:
    return gzip.open(path_or_stream, "rb")


@dataclass(frozen=True)
class MeasurementSite:
    id: str
    version: str
    points: tuple[Point, ...]

    @property
    def key(self) -> str:
        return f"{self.id}@{self.version}"


def read_measurement_sites(stream: BinaryIO) -> Iterator[MeasurementSite]:
    for site in _records(stream, "measurementSite"):
        points: list[Point] = []
        for line in _find(site, "posList"):
            points.extend(_points(line.text or ""))
        if len(points) >= 2:
            yield MeasurementSite(site.attrib["id"], site.attrib.get("version", ""), tuple(points))


@dataclass(frozen=True)
class TravelTime:
    id: str
    version: str
    seconds: float
    normal_seconds: float | None

    @property
    def key(self) -> str:
        return f"{self.id}@{self.version}"


def _duration(base: Element, name: str) -> float | None:
    field = _first(base, name)
    if field is None or _first(field, "dataError") is not None:
        return None
    if field.attrib.get("numberOfInputValuesUsed") == "0":
        return None
    duration = _first(field, "duration")
    if duration is None or not duration.text:
        return None
    value = float(duration.text)
    return value if value > 0 else None


def read_travel_times(stream: BinaryIO) -> Iterator[TravelTime]:
    for measurement in _records(stream, "siteMeasurements"):
        reference = _first(measurement, "measurementSiteReference")
        seconds = _duration(measurement, "travelTime")
        if reference is None or seconds is None:
            continue
        yield TravelTime(
            reference.attrib["id"],
            reference.attrib.get("version", ""),
            seconds,
            _duration(measurement, "normallyExpectedTravelTime"),
        )


@dataclass(frozen=True)
class Closure:
    id: str
    version: str
    points: tuple[Point, ...]
    whole_road: bool  # roadClosed: both directions, also on dual carriageways

    @property
    def key(self) -> str:
        return f"{self.id}@{self.version}"


def _time(text: str | None) -> datetime | None:
    if not text:
        return None
    # NDW delivers nanoseconds; fromisoformat handles at most six digits.
    head, _, rest = text.partition(".")
    if rest:
        digits = "".join(char for char in rest if char.isdigit())
        zone = rest[len(digits) :]
        text = f"{head}.{digits[:6]}{zone}"
    time = datetime.fromisoformat(text.replace("Z", "+00:00"))
    return time if time.tzinfo else time.replace(tzinfo=UTC)


def _valid(record: Element, now: datetime) -> bool:
    specification = _first(record, "validityTimeSpecification")
    if specification is None:
        return True
    start = _time(getattr(_first(specification, "overallStartTime"), "text", None))
    end = _time(getattr(_first(specification, "overallEndTime"), "text", None))
    if start and now < start or end and now > end:
        return False
    # With validPeriods the measure only applies within one of those windows
    # (night closures). Recurring parts of the day do not occur in the feed.
    periods = list(_find(specification, "validPeriod"))
    if not periods:
        return True
    for period in periods:
        period_start = _time(getattr(_first(period, "startOfPeriod"), "text", None))
        period_end = _time(getattr(_first(period, "endOfPeriod"), "text", None))
        if (period_start is None or period_start <= now) and (
            period_end is None or now <= period_end
        ):
            return True
    return False


@dataclass(frozen=True)
class Measure:
    """A valid traffic measure on the road, as the map shows it. A closure for the
    route planner is a special case of it (see `as_closure`)."""

    id: str
    version: str
    management_type: str  # roadOrCarriagewayOrLaneManagementType
    lines: tuple[tuple[Point, ...], ...]  # one per posList, in order
    trucks_only: bool
    carriageway: str | None  # mainCarriageway, exitSlipRoad, ...
    cause: str | None  # causeType
    end: datetime | None
    lanes_open: int | None

    @property
    def key(self) -> str:
        return f"{self.id}@{self.version}"

    @property
    def closes(self) -> bool:
        return self.management_type in CLOSURE_TYPES and not self.trucks_only

    def as_closure(self) -> Closure:
        return Closure(
            self.id,
            self.version,
            tuple(point for line in self.lines for point in line),
            self.management_type == "roadClosed",
        )


def _text(element: Element, name: str) -> str | None:
    """The first `name` with text: DATEX sometimes nests elements with the same
    name (`carriageway` in `carriageway`)."""
    for child in _find(element, name):
        if child.text and child.text.strip():
            return child.text.strip()
    return None


def read_measures(stream: BinaryIO, now: datetime | None = None) -> Iterator[Measure]:
    now = now or datetime.now(UTC)
    for record in _records(stream, "situationRecord"):
        management_type = _text(record, "roadOrCarriagewayOrLaneManagementType")
        if management_type is None or not _valid(record, now):
            continue
        lines = tuple(
            tuple(points)
            for line in _find(record, "posList")
            if len(points := _points(line.text or "")) >= 2
        )
        if not lines:
            continue
        specification = _first(record, "validityTimeSpecification")
        lanes = _text(record, "numberOfOperationalLanes")
        yield Measure(
            record.attrib["id"],
            record.attrib.get("version", ""),
            management_type,
            lines,
            # A closure for trucks only does not exist for a car.
            _first(record, "vehicleType") is not None,
            _text(record, "carriageway"),
            _text(record, "causeType"),
            _time(_text(specification, "overallEndTime")) if specification is not None else None,
            int(lanes) if lanes and lanes.isdigit() else None,
        )


def read_closures(stream: BinaryIO, now: datetime | None = None) -> Iterator[Closure]:
    for measure in read_measures(stream, now):
        if measure.closes:
            yield measure.as_closure()


# From the xsi:type of an SRTI incident to what the app shows.
INCIDENT_KINDS = {
    "Accident": "accident",
    "VehicleObstruction": "breakdown",
    "GeneralObstruction": "obstacle",
}


# An incident without an end stays until the source withdraws it. Arrow trailers
# and crash attenuators of road works companies (also as VehicleObstruction) are
# not always withdrawn: they then stay for days, sometimes weeks. Whatever has
# not been updated for that long can no longer be trusted. Breakdowns and
# accidents from NDW itself are usually gone within a few hours.
INCIDENT_EXPIRES = timedelta(hours=12)

# NDW states for its own incidents how certain they are
# (persistenceEvidenceLevel: 40, 80 or 100). Level 40 holds nearly everything
# that was detected automatically and not yet confirmed: more than a hundred
# "breakdowns" across the country. Only from here on does an incident count;
# without a level always.
INCIDENT_MIN_CONFIDENCE = 80


@dataclass(frozen=True)
class Incident:
    """A safety-related message (SRTI): accident, breakdown or something on the
    road, at a single point."""

    id: str
    kind: str
    point: Point
    bearing: float | None
    since: datetime | None


def read_incidents(stream: BinaryIO, now: datetime | None = None) -> Iterator[Incident]:
    now = now or datetime.now(UTC)
    for record in _records(stream, "situationRecord"):
        kind = INCIDENT_KINDS.get(record.attrib.get(XSI_TYPE, "").rsplit(":", 1)[-1])
        if kind is None or not _valid(record, now):
            continue
        lat, lon = _text(record, "latitude"), _text(record, "longitude")
        if lat is None or lon is None:
            continue
        bearing = _text(record, "bearing")
        specification = _first(record, "validityTimeSpecification")
        since = (
            _time(_text(specification, "overallStartTime")) if specification is not None else None
        )
        updated = _time(_text(record, "situationRecordVersionTime")) or since
        if updated and now - updated > INCIDENT_EXPIRES:
            continue
        confidence = _text(record, "persistenceEvidenceLevel")
        if confidence and float(confidence) < INCIDENT_MIN_CONFIDENCE:
            continue
        yield Incident(
            record.attrib["id"],
            kind,
            (float(lat), float(lon)),
            float(bearing) if bearing else None,
            since,
        )


@dataclass(frozen=True)
class PlannedClosure:
    """A closure from the planning feed, with the windows in which it applies."""

    id: str
    lines: tuple[tuple[Point, ...], ...]
    whole_road: bool
    carriageway: str | None
    windows: tuple[tuple[datetime, datetime | None], ...]  # (start, end)


def _windows(
    record: Element, start: datetime, end: datetime
) -> list[tuple[datetime, datetime | None]]:
    """The validity windows that touch [start, end]. Without validPeriods it is
    one window from beginning to end."""
    specification = _first(record, "validityTimeSpecification")
    if specification is None:
        return []
    overall_start = _time(_text(specification, "overallStartTime"))
    overall_end = _time(_text(specification, "overallEndTime"))
    periods = [
        (_time(_text(p, "startOfPeriod")), _time(_text(p, "endOfPeriod")))
        for p in _find(specification, "validPeriod")
    ] or [(overall_start, overall_end)]
    out = []
    for period_start, period_end in periods:
        period_start = period_start or overall_start
        period_end = period_end or overall_end
        if (
            period_start is None
            or period_start > end
            or (period_end is not None and period_end < start)
        ):
            continue
        out.append((period_start, period_end))
    return out


def read_planned_closures(
    stream: BinaryIO, start: datetime, end: datetime
) -> Iterator[PlannedClosure]:
    """Closures (for cars) that apply somewhere between [start] and [end]."""
    for record in _records(stream, "situationRecord"):
        management_type = _text(record, "roadOrCarriagewayOrLaneManagementType")
        if management_type not in CLOSURE_TYPES or _first(record, "vehicleType") is not None:
            continue
        windows = _windows(record, start, end)
        if not windows:
            continue
        lines = tuple(
            tuple(points)
            for line in _find(record, "posList")
            if len(points := _points(line.text or "")) >= 2
        )
        if lines:
            yield PlannedClosure(
                record.attrib["id"],
                lines,
                management_type == "roadClosed",
                _text(record, "carriageway"),
                tuple(windows),
            )


@dataclass(frozen=True)
class TemporarySpeedLimit:
    """A temporary maximum speed (for road works or an event), with the windows
    in which it applies."""

    id: str
    version: str
    kph: int
    lines: tuple[tuple[Point, ...], ...]
    cause: str | None
    windows: tuple[tuple[datetime, datetime | None], ...]  # (start, end)

    @property
    def key(self) -> str:
        return f"{self.id}@{self.version}"

    @property
    def points(self) -> tuple[Point, ...]:
        return tuple(point for line in self.lines for point in line)

    def applies(self, now: datetime) -> bool:
        return any(start <= now and (end is None or now <= end) for start, end in self.windows)


def read_speed_limits(
    stream: BinaryIO, start: datetime, end: datetime
) -> Iterator[TemporarySpeedLimit]:
    """Temporary maximum speeds that apply somewhere between [start] and [end],
    from the maximum speeds feed or the planning feed (the same records).
    Whatever applies only to some vehicles, or is only advisory, is dropped."""
    for record in _records(stream, "situationRecord"):
        if not record.attrib.get(XSI_TYPE, "").endswith("SpeedManagement"):
            continue
        limit = _text(record, "temporarySpeedLimit")
        compliance = _text(record, "complianceOption")
        if (
            limit is None
            or _first(record, "vehicleType") is not None
            or (compliance is not None and compliance != "mandatory")
        ):
            continue
        try:
            kph = round(float(limit))
        except ValueError:
            continue
        if kph <= 0:
            continue
        windows = _windows(record, start, end)
        if not windows:
            continue
        lines = tuple(
            tuple(points)
            for line in _find(record, "posList")
            if len(points := _points(line.text or "")) >= 2
        )
        if lines:
            yield TemporarySpeedLimit(
                record.attrib["id"],
                record.attrib.get("version", ""),
                kph,
                lines,
                _text(record, "causeType"),
                tuple(windows),
            )


BRIDGE_IN_PROGRESS = {"beingImplemented", "implemented", "beingTerminated"}


@dataclass(frozen=True)
class Bridge:
    """A bridge that is open right now (for shipping): closed to traffic."""

    id: str
    point: Point


def read_bridges(stream: BinaryIO, now: datetime | None = None) -> Iterator[Bridge]:
    """From `actueel_beeld`: bridges that are open right now. A planned opening
    (`approved`) only counts once it is in progress: opening, open, or closing
    again -- in all three traffic is at a standstill."""
    now = now or datetime.now(UTC)
    for record in _records(stream, "situationRecord"):
        management_type = _text(record, "generalNetworkManagementType") or ""
        if (
            not management_type.startswith("bridge")
            or _text(record, "operatorActionStatus") not in BRIDGE_IN_PROGRESS
            or not _valid(record, now)
        ):
            continue
        lat, lon = _text(record, "latitude"), _text(record, "longitude")
        if lat is not None and lon is not None:
            yield Bridge(record.attrib["id"], (float(lat), float(lon)))

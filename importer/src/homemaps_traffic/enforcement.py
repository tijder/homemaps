"""Speed cameras, average speed sections and red light cameras, from the
tileset's OSM file:

- nodes with `highway=speed_camera`;
- relations with `type=enforcement`: the `device` is the camera, `from` and
  `to` are the stretch of road it watches (for `enforcement=average_speed`
  the whole section).

Two passes over the file, with the reader of `osmrules`. The first finds the
tagged nodes and the relations; only blocks that contain one of the words are
parsed. The second looks up where the members of the relations are: those are
often nodes without tags. Nodes are sorted by id in the file, so a block of
nodes is only unpacked when a node we are looking for can be in it.
"""

import bisect
import math
from collections.abc import Iterator
from typing import BinaryIO

from .osmrules import _fields, _packed, _varint, blocks

SPEED_CAMERA = b"speed_camera"
ENFORCEMENT = b"enforcement"

# enforcement=* -> kind in the layer; other checks (weight, noise) are not ours.
KINDS = {"maxspeed": "speed_camera", "traffic_signals": "red_light"}

COMPASS = {
    name: i * 22.5
    for i, name in enumerate("N NNE NE ENE E ESE SE SSE S SSW SW WSW W WNW NW NNW".split())
}

# (lon, lat)
Point = tuple[float, float]


def _signed(value: int) -> int:
    """Zigzag, as protobuf's sint64."""
    return (value >> 1) ^ -(value & 1)


def _deltas(data: bytes) -> list[int]:
    out, total = [], 0
    for value in _packed(data):
        total += _signed(value)
        out.append(total)
    return out


class _Block:
    """One data block: the string table and how to turn lat/lon into degrees."""

    def __init__(self, data: bytes):
        self.strings: list[bytes] = []
        self.groups: list[bytes] = []
        granularity, lat_offset, lon_offset = 100, 0, 0
        for number, value in _fields(data):
            if number == 1:
                self.strings = [string for field, string in _fields(value) if field == 1]
            elif number == 2:
                self.groups.append(value)
            elif number == 17:
                granularity = value
            elif number == 19:
                lat_offset = _signed(value)
            elif number == 20:
                lon_offset = _signed(value)
        self._scale = granularity
        self._offsets = (lon_offset, lat_offset)

    def point(self, lon: int, lat: int) -> Point:
        return (
            round((self._offsets[0] + self._scale * lon) * 1e-9, 7),
            round((self._offsets[1] + self._scale * lat) * 1e-9, 7),
        )

    def tags(self, keys: list[int], values: list[int]) -> dict[str, str]:
        return {
            self.strings[k].decode(errors="replace"): self.strings[v].decode(errors="replace")
            for k, v in zip(keys, values, strict=False)
        }

    def nodes(self, tagged: bool = True) -> Iterator[tuple[int, Point, dict[str, str]]]:
        """(id, point, tags) of every node, plain or dense. With [tagged] off
        the tags are skipped (always empty)."""
        for group in self.groups:
            for number, value in _fields(group):
                if number == 1:
                    node = dict(_fields(value))
                    tags = (
                        self.tags(_packed(node.get(2, b"")), _packed(node.get(3, b"")))
                        if tagged
                        else {}
                    )
                    yield _signed(node[1]), self.point(_signed(node[9]), _signed(node[8])), tags
                elif number == 2:
                    yield from self._dense(dict(_fields(value)), tagged)

    def _dense(self, dense: dict, tagged: bool):
        ids = _deltas(dense.get(1, b""))
        lats, lons = _deltas(dense.get(8, b"")), _deltas(dense.get(9, b""))
        keys_values = _packed(dense.get(10, b"")) if tagged else []
        i = 0
        for node, lat, lon in zip(ids, lats, lons, strict=False):
            tags = {}
            while i < len(keys_values) and keys_values[i] != 0:
                key, value = keys_values[i], keys_values[i + 1]
                tags[self.strings[key].decode(errors="replace")] = self.strings[value].decode(
                    errors="replace"
                )
                i += 2
            i += 1
            yield node, self.point(lon, lat), tags

    def first_node(self) -> int | None:
        """The id of the first node in the block, without unpacking the rest;
        None if there are no nodes in it."""
        for group in self.groups:
            for number, value in _fields(group):
                if number == 1:
                    return _signed(dict(_fields(value))[1])
                if number == 2:
                    for field, ids in _fields(value):
                        if field == 1:
                            return _signed(_varint(ids, 0)[0])
        return None

    def relations(self) -> Iterator[tuple[int, dict[str, str], list[tuple[str, int]]]]:
        """(id, tags, [(role, node id)]) of every relation; members that are not
        nodes are left out."""
        for group in self.groups:
            for number, value in _fields(group):
                if number != 4:
                    continue
                relation = dict(_fields(value))
                tags = self.tags(_packed(relation.get(2, b"")), _packed(relation.get(3, b"")))
                roles = _packed(relation.get(8, b""))
                members = _deltas(relation.get(9, b""))
                types = _packed(relation.get(10, b""))
                yield (
                    relation[1],
                    tags,
                    [
                        (self.strings[role].decode(errors="replace"), member)
                        for role, member, kind in zip(roles, members, types, strict=False)
                        if kind == 0
                    ],
                )


def bearing(a: Point, b: Point) -> float:
    """Compass bearing from a to b, in degrees."""
    lat1, lat2 = math.radians(a[1]), math.radians(b[1])
    dlon = math.radians(b[0] - a[0])
    y = math.sin(dlon) * math.cos(lat2)
    x = math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(dlon)
    return round(math.degrees(math.atan2(y, x)) % 360)


def direction(value: str | None) -> float | None:
    """The `direction` tag of a camera: degrees or a compass point. Other
    values (`forward`, `both`, "90;270") say nothing we can use."""
    if value is None:
        return None
    value = value.strip()
    if value in COMPASS:
        return COMPASS[value]
    try:
        return float(value) % 360
    except ValueError:
        return None


def speed(value: str | None) -> int | None:
    return int(value) if value and value.strip().isdigit() else None


def _feature(point: Point, **properties) -> dict:
    return {
        "type": "Feature",
        "geometry": {"type": "Point", "coordinates": list(point)},
        "properties": {name: value for name, value in properties.items() if value is not None},
    }


def _find(stream: BinaryIO):
    """First pass: camera nodes and enforcement relations."""
    cameras: dict[int, tuple[Point, dict[str, str]]] = {}
    relations: list[tuple[int, dict[str, str], list[tuple[str, int]]]] = []
    for data in blocks(stream):
        has_camera, has_relation = SPEED_CAMERA in data, ENFORCEMENT in data
        if not (has_camera or has_relation):
            continue
        block = _Block(data)
        if has_camera:
            for node, point, tags in block.nodes():
                if tags.get("highway") == "speed_camera":
                    cameras[node] = (point, tags)
        if has_relation:
            for relation in block.relations():
                if relation[1].get("type") == "enforcement" and relation[2]:
                    relations.append(relation)
    return cameras, relations


def _locate(stream: BinaryIO, wanted: set[int]) -> dict[int, Point]:
    """Second pass: where the nodes in [wanted] are."""
    ids = sorted(wanted)
    found: dict[int, Point] = {}
    previous: tuple[int, _Block] | None = None

    def unpack(first: int, block: _Block, next_first: int | None) -> None:
        start = bisect.bisect_left(ids, first)
        end = len(ids) if next_first is None else bisect.bisect_left(ids, next_first)
        if start == end:
            return
        for node, point, _ in block.nodes(tagged=False):
            if node in wanted:
                found[node] = point

    for data in blocks(stream):
        block = _Block(data)
        first = block.first_node()
        if first is None:
            # Past the nodes: ways and relations follow.
            break
        if previous is not None:
            unpack(*previous, first)
        previous = (first, block)
        if len(found) == len(wanted):
            return found
    if previous is not None:
        unpack(*previous, None)
    return found


def enforcement(stream: BinaryIO) -> list[dict]:
    """The layer: Point features with `kind` `speed_camera`, `red_light`,
    `section_start` or `section_end`, and where known `maxspeed` and `bearing`
    (the direction of travel that is checked)."""
    cameras, relations = _find(stream)
    wanted = {node for _, _, members in relations for _, node in members} - cameras.keys()
    points = {node: point for node, (point, _) in cameras.items()}
    if wanted:
        stream.seek(0)
        points |= _locate(stream, wanted)

    features = []
    devices = set()
    for relation, tags, members in relations:
        roles: dict[str, list[int]] = {}
        for role, node in members:
            if node in points:
                roles.setdefault(role, []).append(node)
        devices.update(roles.get("device", []))
        start = (roles.get("from") or [None])[0]
        end = (roles.get("to") or [None])[0]
        heading = bearing(points[start], points[end]) if start and end else None
        limit = speed(tags.get("maxspeed"))
        check = tags.get("enforcement")
        if check == "average_speed":
            if start is None or end is None:
                continue
            for kind, node in (("section_start", start), ("section_end", end)):
                features.append(
                    _feature(
                        points[node],
                        kind=kind,
                        id=f"r{relation}-{kind[8:]}",
                        section=f"r{relation}",
                        maxspeed=limit,
                        bearing=heading,
                    )
                )
        elif check in KINDS:
            # The place on the road; the camera itself may stand beside it.
            node = start or (roles.get("device") or [None])[0]
            if node is None:
                continue
            device = (roles.get("device") or [None])[0]
            device_tags = cameras.get(device, (None, {}))[1]
            features.append(
                _feature(
                    points[node],
                    kind=KINDS[check],
                    id=f"r{relation}",
                    maxspeed=limit or speed(device_tags.get("maxspeed")),
                    bearing=heading
                    if heading is not None
                    else direction(device_tags.get("direction")),
                )
            )

    for node, (point, tags) in cameras.items():
        if node in devices:  # already there through its relation
            continue
        features.append(
            _feature(
                point,
                kind="red_light"
                if tags.get("enforcement") == "traffic_signals"
                else "speed_camera",
                id=f"n{node}",
                maxspeed=speed(tags.get("maxspeed")),
                bearing=direction(tags.get("direction") or tags.get("camera:direction")),
            )
        )
    return features

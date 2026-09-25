import io

from homemaps_traffic import enforcement
from test_osmrules import _block, _field, _packed, _varint


def _zigzag(value: int) -> int:
    return value << 1 if value >= 0 else (-value << 1) - 1


def _deltas(numbers) -> bytes:
    out, previous = [], 0
    for number in numbers:
        out.append(_zigzag(number - previous))
        previous = number
    return _packed(out)


class _Strings:
    def __init__(self):
        self.strings = [b""]

    def __call__(self, text: str) -> int:
        if text.encode() not in self.strings:
            self.strings.append(text.encode())
        return self.strings.index(text.encode())

    def table(self) -> bytes:
        return b"".join(_field(1, s) for s in self.strings)


def _nodes(nodes) -> bytes:
    """A data block with dense [nodes] as (id, lon, lat, {key: value})."""
    strings = _Strings()
    keys_values = []
    for *_, tags in nodes:
        for key, value in tags.items():
            keys_values += [strings(key), strings(value)]
        keys_values.append(0)
    dense = (
        _field(1, _deltas(n[0] for n in nodes))
        + _field(8, _deltas(round(n[2] * 1e7) for n in nodes))
        + _field(9, _deltas(round(n[1] * 1e7) for n in nodes))
        + _field(10, _packed(keys_values))
    )
    return _block(b"OSMData", _field(1, strings.table()) + _field(2, _field(2, dense)))


def _relations(relations) -> bytes:
    """A data block with [relations] as (id, {key: value}, [(role, type, member)])."""
    strings = _Strings()
    group = b""
    for relation_id, tags, members in relations:
        group += _field(
            4,
            _field(1, relation_id)
            + _field(2, _packed(strings(k) for k in tags))
            + _field(3, _packed(strings(v) for v in tags.values()))
            + _field(8, _packed(strings(role) for role, _, _ in members))
            + _field(9, _deltas(member for _, _, member in members))
            + _field(10, _packed(kind for _, kind, _ in members)),
        )
    return _block(b"OSMData", _field(1, strings.table()) + _field(2, group))


NODE, WAY = 0, 1


def _pbf() -> io.BytesIO:
    return io.BytesIO(
        _block(b"OSMHeader", b"")
        # Without tags: only found in the second pass.
        + _nodes([(1, 5.0, 52.0, {}), (2, 5.0, 52.01, {})])
        + _nodes(
            [
                (3, 5.1, 52.1, {"highway": "speed_camera", "maxspeed": "100", "direction": "NE"}),
                (4, 5.2, 52.2, {"highway": "speed_camera", "direction": "180"}),
            ]
        )
        + _nodes([(100, 5.3, 52.3, {}), (101, 5.4, 52.4, {})])
        # Nobody asks for these.
        + _nodes([(200, 6.0, 53.0, {})])
        + _relations(
            [
                (
                    10,
                    {"type": "enforcement", "enforcement": "average_speed", "maxspeed": "100"},
                    [("from", NODE, 1), ("to", NODE, 2), ("device", WAY, 50)],
                ),
                (
                    11,
                    {"type": "enforcement", "enforcement": "maxspeed", "maxspeed": "80"},
                    [("device", NODE, 4), ("from", NODE, 100)],
                ),
                (
                    12,
                    {"type": "enforcement", "enforcement": "traffic_signals"},
                    [("device", NODE, 101), ("from", NODE, 2), ("to", NODE, 1)],
                ),
                (13, {"type": "enforcement", "enforcement": "maxweight"}, [("device", NODE, 1)]),
                (14, {"type": "route"}, [("stop", NODE, 1)]),
            ]
        )
    )


def _by_id(features):
    return {
        f["properties"]["id"]: (f["geometry"]["coordinates"], f["properties"]) for f in features
    }


def test_enforcement():
    found = _by_id(enforcement.enforcement(_pbf()))
    assert found == {
        # The section: start and end, heading north.
        "r10-start": (
            [5.0, 52.0],
            {
                "kind": "section_start",
                "id": "r10-start",
                "section": "r10",
                "maxspeed": 100,
                "bearing": 0,
            },
        ),
        "r10-end": (
            [5.0, 52.01],
            {
                "kind": "section_end",
                "id": "r10-end",
                "section": "r10",
                "maxspeed": 100,
                "bearing": 0,
            },
        ),
        # On the road at `from`, the direction from the camera's tag.
        "r11": (
            [5.3, 52.3],
            {"kind": "speed_camera", "id": "r11", "maxspeed": 80, "bearing": 180.0},
        ),
        # From `from` to `to`: south.
        "r12": ([5.0, 52.01], {"kind": "red_light", "id": "r12", "bearing": 180}),
        # A camera without a relation; node 4 is the device of r11.
        "n3": (
            [5.1, 52.1],
            {"kind": "speed_camera", "id": "n3", "maxspeed": 100, "bearing": 45.0},
        ),
    }


def test_nodes_only():
    """Without relations there is no second pass."""
    stream = io.BytesIO(
        _block(b"OSMHeader", b"")
        + _nodes([(7, 4.9, 52.37, {"highway": "speed_camera", "enforcement": "traffic_signals"})])
    )
    assert _by_id(enforcement.enforcement(stream)) == {
        "n7": ([4.9, 52.37], {"kind": "red_light", "id": "n7"})
    }


def test_direction():
    assert enforcement.direction("NE") == 45
    assert enforcement.direction("270") == 270
    assert enforcement.direction("-90") == 270
    for value in (None, "forward", "both", "90;270"):
        assert enforcement.direction(value) is None


def test_signed_varint_roundtrip():
    # Negative coordinates (west of Greenwich) go through zigzag.
    data = _field(1, _deltas([-5, 3]))
    assert enforcement._deltas(dict(enforcement._fields(data))[1]) == [-5, 3]
    assert _varint(0) == b"\x00"

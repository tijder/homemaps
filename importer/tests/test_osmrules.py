import io
import struct
import zlib

from homemaps_traffic import osmrules


def _varint(value: int) -> bytes:
    out = bytearray()
    while True:
        byte = value & 0x7F
        value >>= 7
        if value:
            out.append(byte | 0x80)
        else:
            out.append(byte)
            return bytes(out)


def _field(number: int, value) -> bytes:
    if isinstance(value, int):
        return _varint(number << 3) + _varint(value)
    return _varint(number << 3 | 2) + _varint(len(value)) + value


def _packed(numbers) -> bytes:
    return b"".join(_varint(n) for n in numbers)


def _block(block_type: bytes, content: bytes, compress=True) -> bytes:
    blob = (
        _field(2, len(content)) + _field(3, zlib.compress(content))
        if compress
        else _field(1, content)
    )
    header = _field(1, block_type) + _field(3, len(blob))
    return struct.pack(">I", len(header)) + header + blob


def _pbf(ways, compress=True) -> io.BytesIO:
    """A minimal PBF file: a header block and one block with [ways] as
    (id, {key: value})."""
    strings = [b""]
    for _, tags in ways:
        for string in (*tags, *tags.values()):
            if string.encode() not in strings:
                strings.append(string.encode())
    table = b"".join(_field(1, s) for s in strings)
    group = b""
    for way_id, tags in ways:
        keys = [strings.index(k.encode()) for k in tags]
        values = [strings.index(v.encode()) for v in tags.values()]
        way = _field(1, way_id) + _field(2, _packed(keys)) + _field(3, _packed(values))
        group += _field(3, way)
    block = _field(1, table) + _field(2, group)
    head = _block(b"OSMHeader", b"", compress)
    # A block without the tag is skipped; it may simply be there.
    empty = _field(1, _field(1, b"") + _field(1, b"highway")) + _field(2, b"")
    return io.BytesIO(
        head + _block(b"OSMData", empty, compress) + _block(b"OSMData", block, compress)
    )


def test_read_pbf():
    ways = [
        (
            7014267,
            {
                "highway": "motorway",
                "maxspeed": "100",
                "maxspeed:conditional": "130 @ (19:00-06:00)",
            },
        ),
        (2, {"highway": "primary", "maxspeed": "80"}),
        # Not a road: does not count.
        (3, {"railway": "rail", "maxspeed:conditional": "40 @ (22:00-06:00)"}),
        (300000000000, {"highway": "trunk", "maxspeed:conditional": "70 @ wet"}),
    ]
    for compress in (True, False):
        assert osmrules.read_pbf(_pbf(ways, compress)) == {
            7014267: "130 @ (19:00-06:00)",
            300000000000: "70 @ wet",
        }


def test_conditional_speeds_only_usable_rules():
    ways = [
        (1, {"highway": "motorway", "maxspeed:conditional": "130 @ (19:00-06:00)"}),
        (2, {"highway": "trunk", "maxspeed:conditional": "70 @ wet"}),
    ]
    assert osmrules.conditional_speeds(_pbf(ways)) == {"1": [(130, 127, [(1140, 360)])]}


def test_rules():
    every = osmrules.EVERY_DAY
    weekdays = 0b0011111
    assert osmrules.rules("130 @ (19:00-06:00)") == [(130, every, [(1140, 360)])]
    assert osmrules.rules("100 @ (06:00-19:00)") == [(100, every, [(360, 1140)])]
    # Days and multiple windows, with and without parentheses.
    assert osmrules.rules("100 @ (Mo-Fr 06:00-10:00,15:00-19:00)") == [
        (100, weekdays, [(360, 600), (900, 1140)])
    ]
    assert osmrules.rules("80 @ Sa,Su 7:30-9:00") == [(80, 0b1100000, [(450, 540)])]
    # Multiple rules within the condition, and "PH off" does not count.
    assert osmrules.rules("30 @ (Mo-Fr 07:00-09:00; Sa 10:00-12:00; PH off)") == [
        (30, weekdays, [(420, 540)]),
        (30, 0b0100000, [(600, 720)]),
    ]
    # Two speeds; wet weather is dropped.
    assert osmrules.rules("130 @ (19:00-06:00); 70 @ wet") == [(130, every, [(1140, 360)])]
    # Whatever does not depend on the clock or cannot be read.
    for text in (
        "70 @ wet",
        '100 @ Mo-Fr 06:00-10:00,15:00-19:00 "bij grote verkeersdrukte"',
        "none @ (sunrise-sunset)",
        "30 @ (2026 Jul 17-2027 Apr 21)",
        "30 @ school",
        "@ (19:00-06:00)",
        "130",
    ):
        assert osmrules.rules(text) == [], text
    # A day range across the weekend.
    assert osmrules.rules("50 @ (Fr-Mo 00:00-24:00)")[0][1] == 0b1110001

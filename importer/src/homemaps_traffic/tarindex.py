"""Opening traffic.tar and updating edges in place in the file.

Valhalla keeps this file open via mmap. That is why writes go exclusively *into*
the file, via a shared mmap: putting a new file next to it and renaming it
would leave Valhalla looking at the old inode until the next restart.
"""

import mmap
import tarfile
import time
from dataclasses import dataclass
from pathlib import Path

from . import traffictile as tt


@dataclass(frozen=True)
class Tile:
    start: int  # byte offset of the header in the tar file
    edge_count: int


class TrafficTar:
    def __init__(self, path: str | Path):
        self.path = Path(path)
        self.tiles: dict[int, Tile] = {}
        with tarfile.open(self.path, "r:") as tar:
            # Only the tiles: valhalla_build_extract also adds an index.bin
            # (112 bytes), and reading that as a header yields nonsense.
            members = [
                (member.offset_data, member.size)
                for member in tar
                if member.isfile() and member.name.endswith(".gph")
            ]
        self._file = open(self.path, "r+b")
        self._map = mmap.mmap(self._file.fileno(), 0, flags=mmap.MAP_SHARED)
        for start, size in members:
            if size < tt.HEADER_SIZE:
                continue
            header = tt.Header.read(self._map[start : start + tt.HEADER_SIZE])
            expected = tt.HEADER_SIZE + header.directed_edge_count * tt.RECORD_SIZE
            if size < expected:
                raise ValueError(f"tile {header.tile_id}: {size} bytes, expected {expected}")
            self.tiles[header.tile_id] = Tile(start, header.directed_edge_count)

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.close()

    def close(self):
        self._map.flush()
        self._map.close()
        self._file.close()

    @property
    def edge_count(self) -> int:
        return sum(tile.edge_count for tile in self.tiles.values())

    def _offset(self, graphid: int) -> int | None:
        tile = self.tiles.get(tt.tile_of(graphid))
        if tile is None:
            return None
        index = tt.index_of(graphid)
        if index >= tile.edge_count:
            return None
        return tile.start + tt.HEADER_SIZE + index * tt.RECORD_SIZE

    def read(self, graphid: int) -> int | None:
        offset = self._offset(graphid)
        if offset is None:
            return None
        return tt.RECORD.unpack_from(self._map, offset)[0]

    def write(self, graphid: int, value: int) -> bool:
        """One record. A uint64 at an aligned address is a single unit for the
        reader; Valhalla reads this field as `volatile`."""
        offset = self._offset(graphid)
        if offset is None:
            return False
        tt.RECORD.pack_into(self._map, offset, value)
        return True

    def update(self, new: dict[int, int], previous: set[int]) -> tuple[int, int, int]:
        """Writes `new` and resets everything from `previous` that is no longer in
        it to unknown. Valhalla has no expiry: whatever is not cleared here stays
        in effect forever.

        Returns (written, cleared, unknown edge ids).
        """
        written = cleared = unknown = 0
        for graphid, value in new.items():
            if self.write(graphid, value):
                written += 1
            else:
                unknown += 1
        for graphid in previous - new.keys():
            if self.write(graphid, tt.UNKNOWN):
                cleared += 1
        self._stamp()
        self._map.flush()
        return written, cleared, unknown

    def clear_all(self) -> None:
        """After a restart of the importer it is unknown what a previous instance
        had written; then the cycle starts with a clean slate."""
        for tile in self.tiles.values():
            start = tile.start + tt.HEADER_SIZE
            end = start + tile.edge_count * tt.RECORD_SIZE
            self._map[start:end] = bytes(end - start)
        self._stamp()
        self._map.flush()

    def _stamp(self) -> None:
        now = int(time.time())
        for tile_id, tile in self.tiles.items():
            tt.HEADER.pack_into(
                self._map, tile.start, tile_id, now, tile.edge_count, tt.TILE_VERSION, 0, 0
            )

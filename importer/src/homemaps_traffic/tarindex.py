"""traffic.tar openen en edges op hun plek in het bestand bijwerken.

Valhalla houdt dit bestand via mmap open. Daarom wordt er uitsluitend *in* het
bestand geschreven, via een gedeelde mmap: een nieuw bestand ernaast zetten en
hernoemen zou Valhalla op de oude inode laten kijken tot de volgende herstart.
"""

import mmap
import tarfile
import time
from dataclasses import dataclass
from pathlib import Path

from . import traffictile as tt


@dataclass(frozen=True)
class Tegel:
    begin: int  # byte-offset van de header in het tar-bestand
    aantal_edges: int


class TrafficTar:
    def __init__(self, pad: str | Path):
        self.pad = Path(pad)
        self.tegels: dict[int, Tegel] = {}
        with tarfile.open(self.pad, "r:") as tar:
            # Alleen de tegels: valhalla_build_extract zet er ook een index.bin bij
            # (112 bytes), en die als header lezen levert onzin op.
            leden = [
                (lid.offset_data, lid.size)
                for lid in tar
                if lid.isfile() and lid.name.endswith(".gph")
            ]
        self._bestand = open(self.pad, "r+b")
        self._map = mmap.mmap(self._bestand.fileno(), 0, flags=mmap.MAP_SHARED)
        for begin, grootte in leden:
            if grootte < tt.HEADER_SIZE:
                continue
            header = tt.Header.lees(self._map[begin : begin + tt.HEADER_SIZE])
            verwacht = tt.HEADER_SIZE + header.directed_edge_count * tt.RECORD_SIZE
            if grootte < verwacht:
                raise ValueError(f"tegel {header.tile_id}: {grootte} bytes, verwacht {verwacht}")
            self.tegels[header.tile_id] = Tegel(begin, header.directed_edge_count)

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.sluit()

    def sluit(self):
        self._map.flush()
        self._map.close()
        self._bestand.close()

    @property
    def aantal_edges(self) -> int:
        return sum(tegel.aantal_edges for tegel in self.tegels.values())

    def _plek(self, graphid: int) -> int | None:
        tegel = self.tegels.get(tt.tegel_van(graphid))
        if tegel is None:
            return None
        index = tt.index_van(graphid)
        if index >= tegel.aantal_edges:
            return None
        return tegel.begin + tt.HEADER_SIZE + index * tt.RECORD_SIZE

    def lees(self, graphid: int) -> int | None:
        plek = self._plek(graphid)
        if plek is None:
            return None
        return tt.RECORD.unpack_from(self._map, plek)[0]

    def schrijf(self, graphid: int, waarde: int) -> bool:
        """Eén record. Een uint64 op een uitgelijnd adres is voor de lezer één
        geheel; Valhalla leest dit veld als `volatile`."""
        plek = self._plek(graphid)
        if plek is None:
            return False
        tt.RECORD.pack_into(self._map, plek, waarde)
        return True

    def werk_bij(self, nieuw: dict[int, int], vorige: set[int]) -> tuple[int, int, int]:
        """Schrijft `nieuw` en zet alles uit `vorige` dat er niet meer in zit terug
        op onbekend. Valhalla kent geen veroudering: wat hier niet wordt gewist,
        blijft voor altijd gelden.

        Geeft (geschreven, gewist, onbekende edge-id's) terug.
        """
        geschreven = gewist = onbekend = 0
        for graphid, waarde in nieuw.items():
            if self.schrijf(graphid, waarde):
                geschreven += 1
            else:
                onbekend += 1
        for graphid in vorige - nieuw.keys():
            if self.schrijf(graphid, tt.ONBEKEND):
                gewist += 1
        self._stempel()
        self._map.flush()
        return geschreven, gewist, onbekend

    def wis_alles(self) -> None:
        """Na een herstart van de importer is onbekend wat een vorige instantie
        had geschreven; dan begint de ronde met een schone lei."""
        for tegel in self.tegels.values():
            begin = tegel.begin + tt.HEADER_SIZE
            eind = begin + tegel.aantal_edges * tt.RECORD_SIZE
            self._map[begin:eind] = bytes(eind - begin)
        self._stempel()
        self._map.flush()

    def _stempel(self) -> None:
        nu = int(time.time())
        for tile_id, tegel in self.tegels.items():
            tt.HEADER.pack_into(
                self._map, tegel.begin, tile_id, nu, tegel.aantal_edges, tt.TILE_VERSION, 0, 0
            )

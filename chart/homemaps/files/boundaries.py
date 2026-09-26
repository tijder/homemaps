"""Fetches the country and province boundaries around a bounding box from
Overpass, complete, for valhalla_build_admins.

The Geofabrik extract is not enough: it contains the country relations, but not
the member ways outside the region (the Netherlands without the Caribbean
islands). Valhalla then skips the country as "degenerate", every road ends up in
no country at all -- and so drives on the left: roundabout exits are counted
clockwise, and the country's access rules are missing.

Overpass is regularly busy (504, or an HTML page with HTTP 200, or a <remark>
with an error in an otherwise valid document), hence the check on the content
and the patient attempts.

Usage: boundaries.py <minlon,minlat,maxlon,maxlat> <output .osm>
"""

import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

OVERPASS = "https://overpass-api.de/api/interpreter"


def query(minlon, minlat, maxlon, maxlat):
    # The levels Valhalla's admin.lua reads: 2 and 4, and 3 because it takes
    # France as "Metropolitan France" (level 3), not level 2. Only the relations
    # need their tags; skeletons of the ways and nodes are enough for the
    # geometry and keep the file small.
    return (
        "[timeout:600];"
        f'rel[boundary=administrative][admin_level~"^[234]$"]({minlat},{minlon},{maxlat},{maxlon})->.b;'
        ".b out body;way(r.b);out skel qt;node(w);out skel qt;"
    )


def complete(data):
    head, tail = data[:1000], data[-1000:]
    return b"<osm" in head and b"</osm>" in tail and b"<remark>" not in tail


def main():
    bbox = [float(part) for part in sys.argv[1].split(",")]
    target = Path(sys.argv[2])
    body = urllib.parse.urlencode({"data": query(*bbox)}).encode()
    request = urllib.request.Request(
        OVERPASS, data=body, headers={"User-Agent": "homemaps-valhalla-build"}
    )
    for attempt in range(1, 7):
        try:
            with urllib.request.urlopen(request, timeout=900) as response:
                data = response.read()
            if complete(data):
                temporary = target.with_suffix(".part")
                temporary.write_bytes(data)
                temporary.rename(target)
                print(f"{target}: {len(data) >> 20} MiB", flush=True)
                return
            print(f"attempt {attempt}: no complete answer from Overpass", flush=True)
        except OSError as error:
            print(f"attempt {attempt}: {error}", flush=True)
        time.sleep(60 * attempt)
    sys.exit(f"boundaries failed: {OVERPASS}")


if __name__ == "__main__":
    main()

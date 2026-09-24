"""Fetches the SRTM elevation tiles (Tilezen "skadi") for a bounding box.

Replaces valhalla_build_elevation: that script opens its connections without a
timeout and hung here without an error on an empty output file. The tiles are
plain files with a fixed pattern -- N52/N52E004.hgt.gz, one per square degree --
and Valhalla reads the .gz directly.

Usage: elevation.py <minlon,minlat,maxlon,maxlat> <output dir>
"""

import math
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

SOURCE = "https://elevation-tiles-prod.s3.us-east-1.amazonaws.com/skadi"


def tiles(minlon, minlat, maxlon, maxlat):
    for lat in range(math.floor(minlat), math.floor(maxlat) + 1):
        for lon in range(math.floor(minlon), math.floor(maxlon) + 1):
            ns = f"{'N' if lat >= 0 else 'S'}{abs(lat):02d}"
            ew = f"{'E' if lon >= 0 else 'W'}{abs(lon):03d}"
            yield ns, f"{ns}{ew}.hgt.gz"


def fetch(url, target):
    for attempt in range(4):
        try:
            with urllib.request.urlopen(url, timeout=60) as response:
                data = response.read()
            temporary = target.with_suffix(".part")
            temporary.write_bytes(data)
            temporary.rename(target)
            return True
        except urllib.error.HTTPError as error:
            # Over sea there is no tile; that is not an error.
            if error.code in (403, 404):
                return False
            print(f"  attempt {attempt + 1}: {error}", flush=True)
        except OSError as error:
            print(f"  attempt {attempt + 1}: {error}", flush=True)
        time.sleep(5 * (attempt + 1))
    sys.exit(f"fetch failed: {url}")


def main():
    bbox = [float(part) for part in sys.argv[1].split(",")]
    out = Path(sys.argv[2])
    for directory, name in tiles(*bbox):
        target = out / directory / name
        if target.exists():
            print(f"{name} already present", flush=True)
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        fetched = fetch(f"{SOURCE}/{directory}/{name}", target)
        print(f"{name} {'fetched' if fetched else 'does not exist (sea)'}", flush=True)


if __name__ == "__main__":
    main()

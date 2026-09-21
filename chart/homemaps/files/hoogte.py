"""Haalt de SRTM-hoogtetegels (Tilezen "skadi") voor een bounding box op.

Vervangt valhalla_build_elevation: dat script opent zijn verbindingen zonder
time-out en bleef hier zonder foutmelding hangen op een leeg uitvoerbestand. De
tegels zijn gewone bestanden met een vast patroon -- N52/N52E004.hgt.gz, één per
vierkante graad -- en Valhalla leest de .gz rechtstreeks.

Gebruik: hoogte.py <minlon,minlat,maxlon,maxlat> <uitvoermap>
"""

import math
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

BRON = "https://elevation-tiles-prod.s3.us-east-1.amazonaws.com/skadi"


def tegels(minlon, minlat, maxlon, maxlat):
    for lat in range(math.floor(minlat), math.floor(maxlat) + 1):
        for lon in range(math.floor(minlon), math.floor(maxlon) + 1):
            ns = f"{'N' if lat >= 0 else 'S'}{abs(lat):02d}"
            ew = f"{'E' if lon >= 0 else 'W'}{abs(lon):03d}"
            yield ns, f"{ns}{ew}.hgt.gz"


def haal(url, doel):
    for poging in range(4):
        try:
            with urllib.request.urlopen(url, timeout=60) as antwoord:
                data = antwoord.read()
            tijdelijk = doel.with_suffix(".deel")
            tijdelijk.write_bytes(data)
            tijdelijk.rename(doel)
            return True
        except urllib.error.HTTPError as fout:
            # Boven zee bestaat er geen tegel; dat is geen fout.
            if fout.code in (403, 404):
                return False
            print(f"  poging {poging + 1}: {fout}", flush=True)
        except OSError as fout:
            print(f"  poging {poging + 1}: {fout}", flush=True)
        time.sleep(5 * (poging + 1))
    sys.exit(f"ophalen mislukt: {url}")


def main():
    bbox = [float(deel) for deel in sys.argv[1].split(",")]
    uit = Path(sys.argv[2])
    for map_, naam in tegels(*bbox):
        doel = uit / map_ / naam
        if doel.exists():
            print(f"{naam} staat er al", flush=True)
            continue
        doel.parent.mkdir(parents=True, exist_ok=True)
        gelukt = haal(f"{BRON}/{map_}/{naam}", doel)
        print(f"{naam} {'opgehaald' if gelukt else 'bestaat niet (zee)'}", flush=True)


if __name__ == "__main__":
    main()

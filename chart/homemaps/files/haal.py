"""Haalt één bestand op, met time-outs en een paar pogingen, en zet het pas op
zijn plek als het compleet is. Het Valhalla-image heeft geen curl of wget."""

import shutil
import sys
import time
import urllib.request
from pathlib import Path

url, doel = sys.argv[1], Path(sys.argv[2])
tijdelijk = doel.with_suffix(doel.suffix + ".deel")
for poging in range(1, 5):
    try:
        with urllib.request.urlopen(url, timeout=60) as bron, open(tijdelijk, "wb") as uit:
            shutil.copyfileobj(bron, uit, 1 << 20)
        tijdelijk.rename(doel)
        print(f"{doel}: {doel.stat().st_size >> 20} MiB", flush=True)
        sys.exit(0)
    except OSError as fout:
        print(f"poging {poging}: {fout}", flush=True)
        time.sleep(15 * poging)
sys.exit(f"ophalen mislukt: {url}")

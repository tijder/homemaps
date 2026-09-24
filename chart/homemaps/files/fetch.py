"""Fetches a single file, with timeouts and a few attempts, and only puts it in
place once it is complete. The Valhalla image has no curl or wget."""

import shutil
import sys
import time
import urllib.request
from pathlib import Path

url, target = sys.argv[1], Path(sys.argv[2])
temporary = target.with_suffix(target.suffix + ".part")
for attempt in range(1, 5):
    try:
        with urllib.request.urlopen(url, timeout=60) as source, open(temporary, "wb") as out:
            shutil.copyfileobj(source, out, 1 << 20)
        temporary.rename(target)
        print(f"{target}: {target.stat().st_size >> 20} MiB", flush=True)
        sys.exit(0)
    except OSError as error:
        print(f"attempt {attempt}: {error}", flush=True)
        time.sleep(15 * attempt)
sys.exit(f"fetch failed: {url}")

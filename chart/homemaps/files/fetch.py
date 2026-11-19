"""Fetches a single file, with timeouts and a few attempts, and only puts it in
place once it is complete. The Valhalla image has no curl or wget."""

import http.client
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
            expected = source.headers.get("Content-Length")
        # A connection that closes early ends the copy without an error: only
        # the length tells that the file is not all there.
        size = temporary.stat().st_size
        if expected is not None and size != int(expected):
            raise OSError(f"got {size} of {expected} bytes")
        temporary.rename(target)
        print(f"{target}: {target.stat().st_size >> 20} MiB", flush=True)
        sys.exit(0)
    except (OSError, http.client.HTTPException) as error:
        print(f"attempt {attempt}: {error}", flush=True)
        time.sleep(15 * attempt)
sys.exit(f"fetch failed: {url}")

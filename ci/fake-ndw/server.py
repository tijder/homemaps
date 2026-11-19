"""The web server of the test bed: the fake NDW feeds, and the map sources the
build jobs would otherwise fetch from Geofabrik, GraphHopper and Overpass.

Serves /feeds (the ConfigMap with the fake feeds) and, for what is not there,
/srv (the files ci/sources.sh keeps, copied in by ci/up.sh: too large for a
ConfigMap). A POST to /api/interpreter is Overpass: the answer is
/srv/boundaries.osm, whatever the query.
"""

import http.server
import os
import shutil
import sys

ROOTS = sys.argv[2:] or ["/feeds", "/srv"]


class Handler(http.server.SimpleHTTPRequestHandler):
    def translate_path(self, path):
        name = path.split("?", 1)[0].lstrip("/")
        for root in ROOTS:
            candidate = os.path.join(root, name)
            if os.path.isfile(candidate):
                return candidate
        return os.path.join(ROOTS[0], name)

    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length") or 0))
        path = self.translate_path("/boundaries.osm")
        if self.path.split("?", 1)[0] != "/api/interpreter" or not os.path.isfile(path):
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Type", "application/osm3s+xml")
        self.send_header("Content-Length", str(os.path.getsize(path)))
        self.end_headers()
        with open(path, "rb") as source:
            shutil.copyfileobj(source, self.wfile)


if __name__ == "__main__":
    http.server.ThreadingHTTPServer(("", int(sys.argv[1])), Handler).serve_forever()

#!/usr/bin/env bash
# Keeps the map sources of the test bed in ci/.work/sources: Andorra's OSM
# extract, its Photon index and the country boundaries. ci/up.sh serves them
# from fake-ndw, so a run does not depend on Geofabrik, GraphHopper and
# Overpass all being up -- and the roads the fake traffic lies on stay where
# they are until the files are refreshed.
#
#   ci/sources.sh            fetch what is missing
#   REFRESH=1 ci/sources.sh  fetch everything anew; what fails keeps its old copy
#
# Exits non-zero only if a file is missing afterwards.
set -uo pipefail
cd "$(dirname "$0")/.."
DIR=ci/.work/sources
BBOX=$(sed -n 's/^  bbox: "\(.*\)"/\1/p' ci/values-andorra.yaml)
mkdir -p "$DIR"

# fetch <url> <name>: to a temporary file first, so a failure leaves the old one.
fetch() {
  local url=$1 target=$DIR/$2
  [ -s "$target" ] && [ -z "${REFRESH:-}" ] && return 0
  if curl -fsSL --retry 2 --max-time 300 -o "$target.part" "$url" && [ -s "$target.part" ]; then
    mv "$target.part" "$target"
    echo "fetched $2"
  else
    rm -f "$target.part"
    echo "could not fetch $2 from $url$([ -s "$target" ] && echo '; keeping the copy that is there')"
  fi
}

fetch https://download.geofabrik.de/europe/andorra-latest.osm.pbf andorra-latest.osm.pbf
PHOTON=https://download1.graphhopper.com/public/europe/andorra/photon-db-andorra-1.0-latest.tar.bz2
# The index and its checksum belong together: both, or neither.
if [ ! -s "$DIR/photon-db-andorra-1.0-latest.tar.bz2.md5" ] || [ -n "${REFRESH:-}" ]; then
  mkdir -p "$DIR/photon.new"
  if curl -fsSL --retry 2 --max-time 300 -o "$DIR/photon.new/db" "$PHOTON" &&
     curl -fsSL --retry 2 --max-time 60 -o "$DIR/photon.new/md5" "$PHOTON.md5" &&
     [ "$(md5sum < "$DIR/photon.new/db" | cut -d' ' -f1)" = "$(cut -d' ' -f1 < "$DIR/photon.new/md5")" ]; then
    mv "$DIR/photon.new/db" "$DIR/photon-db-andorra-1.0-latest.tar.bz2"
    mv "$DIR/photon.new/md5" "$DIR/photon-db-andorra-1.0-latest.tar.bz2.md5"
    echo "fetched the Photon index"
  else
    echo "could not fetch the Photon index"
  fi
  rm -rf "$DIR/photon.new"
fi
# The boundaries with the chart's own script, so the query is the real one.
# One attempt here; the script itself retries a busy Overpass for a while.
if [ ! -s "$DIR/boundaries.osm" ] || [ -n "${REFRESH:-}" ]; then
  if timeout 600 python3 chart/homemaps/files/boundaries.py "$BBOX" "$DIR/boundaries.new" >/dev/null 2>&1 &&
     [ -s "$DIR/boundaries.new" ]; then
    mv "$DIR/boundaries.new" "$DIR/boundaries.osm"
    echo "fetched the boundaries"
  else
    echo "could not fetch the boundaries from Overpass"
  fi
  rm -f "$DIR/boundaries.new" "$DIR/boundaries.part"
fi

missing=0
for name in andorra-latest.osm.pbf photon-db-andorra-1.0-latest.tar.bz2 \
            photon-db-andorra-1.0-latest.tar.bz2.md5 boundaries.osm; do
  [ -s "$DIR/$name" ] || { echo "missing: $DIR/$name"; missing=1; }
done
exit $missing

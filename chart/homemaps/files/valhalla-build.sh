#!/bin/bash
# Builds a fresh Valhalla tileset in /data/new. The swap to /data/active is done by
# the next container, and only if this script succeeded.
set -euo pipefail

PBF=/data/source/region.osm.pbf
mkdir -p /data/source /data/elevation
rm -rf /data/new && mkdir -p /data/new

echo "== fetching PBF: $PBF_URL"
python3 /script/fetch.py "$PBF_URL" "$PBF"

if [ -n "${ELEVATION_BBOX:-}" ]; then
  echo "== elevation tiles for $ELEVATION_BBOX"
  python3 /script/elevation.py "$ELEVATION_BBOX" /data/elevation
fi

cd /data/new
valhalla_build_config \
  --mjolnir-tile-dir /data/new/tiles \
  --mjolnir-tile-extract /data/new/tiles.tar \
  --mjolnir-traffic-extract /data/new/traffic.tar \
  --mjolnir-timezone /data/new/timezones.sqlite \
  --mjolnir-admin /data/new/admins.sqlite \
  --additional-data-elevation /data/elevation \
  --mjolnir-concurrency "${BUILD_THREADS:-2}" > build.json

echo "== time zones and administrative boundaries"
valhalla_build_timezones > timezones.sqlite
valhalla_build_admins -c build.json "$PBF"
echo "== tiles"
valhalla_build_tiles -c build.json "$PBF"
echo "== extract with the empty traffic skeleton"
valhalla_build_extract -c build.json -v --with-traffic --overwrite
# The individual tiles are now in tiles.tar; the directory is just dead weight.
rm -rf /data/new/tiles build.json
test -s /data/new/tiles.tar && test -s /data/new/traffic.tar
echo "== done"

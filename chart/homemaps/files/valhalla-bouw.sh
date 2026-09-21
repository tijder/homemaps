#!/bin/bash
# Bouwt een verse Valhalla-tileset in /data/nieuw. De wissel naar /data/actief doet
# de volgende container, en alleen als dit script geslaagd is.
set -euo pipefail

PBF=/data/bron/gebied.osm.pbf
mkdir -p /data/bron /data/hoogte
rm -rf /data/nieuw && mkdir -p /data/nieuw

echo "== PBF ophalen: $PBF_URL"
python3 /script/haal.py "$PBF_URL" "$PBF"

if [ -n "${HOOGTE_BBOX:-}" ]; then
  echo "== hoogtetegels voor $HOOGTE_BBOX"
  python3 /script/hoogte.py "$HOOGTE_BBOX" /data/hoogte
fi

cd /data/nieuw
valhalla_build_config \
  --mjolnir-tile-dir /data/nieuw/tiles \
  --mjolnir-tile-extract /data/nieuw/tiles.tar \
  --mjolnir-traffic-extract /data/nieuw/traffic.tar \
  --mjolnir-timezone /data/nieuw/timezones.sqlite \
  --mjolnir-admin /data/nieuw/admins.sqlite \
  --additional-data-elevation /data/hoogte \
  --mjolnir-concurrency "${BOUW_THREADS:-2}" > bouw.json

echo "== tijdzones en bestuurlijke grenzen"
valhalla_build_timezones > timezones.sqlite
valhalla_build_admins -c bouw.json "$PBF"
echo "== tiles"
valhalla_build_tiles -c bouw.json "$PBF"
echo "== extract met het lege verkeersskelet"
valhalla_build_extract -c bouw.json -v --with-traffic --overwrite
# De losse tegels zitten nu in tiles.tar; de map is alleen nog ballast.
rm -rf /data/nieuw/tiles bouw.json
test -s /data/nieuw/tiles.tar && test -s /data/nieuw/traffic.tar
echo "== klaar"

#!/usr/bin/env bash
# Checks in the cluster that the importer has put the fake feed into Valhalla:
# the jam on the CG-2 makes "depart now" slower than the same route without live
# traffic, and the closed street is avoided.
set -euo pipefail
CLUSTER=$1 NS=$2 RELEASE=$3
K="kubectl --context kind-$CLUSTER -n $NS"
POD=$($K get pod -l app.kubernetes.io/component=valhalla -o name | head -1)

query() { $K exec "$POD" -c traffic -- python3 -c "
import json, sys, urllib.request
r = urllib.request.urlopen(urllib.request.Request('http://localhost:8002/route', sys.argv[1].encode()), timeout=30)
print(json.load(r)['trip']['summary']['time'])" "$1"; }

ROUTE='"locations":[{"lat":42.5361,"lon":1.5828},{"lat":42.5670,"lon":1.5990}],"costing":"auto","date_time":{"type":0}'
echo "waiting for the importer's first cycle"
for _ in $(seq 1 30); do
  edges=$($K exec "$POD" -c traffic -- python3 -c "
import urllib.request
for line in urllib.request.urlopen('http://localhost:9100/metrics', timeout=5).read().decode().splitlines():
    if line.startswith('homemaps_traffic_edges_with_speed '): print(int(float(line.split()[1])))" 2>/dev/null || echo 0)
  [ "${edges:-0}" -gt 0 ] && break
  sleep 10
done
echo "edges with live speed: ${edges:-0}"
[ "${edges:-0}" -gt 0 ] || { $K logs "$POD" -c traffic --tail=40; exit 1; }

live=$(query "{$ROUTE}")
without=$(query "{$ROUTE,\"costing_options\":{\"auto\":{\"speed_types\":[\"freeflow\",\"constrained\",\"predicted\"]}}}")
echo "CG-2 with live traffic: ${live}s, without: ${without}s"
python3 -c "import sys; sys.exit(0 if float('$live') > float('$without') * 1.5 else 'live traffic has no effect')"
echo "live traffic works"

# The map layer from the same cycle: the jam, the closure, the accident, the
# temporary speed limit, the MSI sign gantry and the open bridge from the fake
# feed. The speed limit is on the CG-2, one carriageway: once or twice (there, and
# back if that runs over the same way).
kinds=$($K exec "$POD" -c traffic -- python3 -c "
import json, urllib.request
layer = json.load(urllib.request.urlopen('http://localhost:9100/traffic.geojson', timeout=5))
print(' '.join(sorted({f['properties']['kind'] for f in layer['features']})))")
echo "map layer: $kinds"
[ "$kinds" = "accident bridge closed jam msi speed_limit" ] || { echo "map layer is wrong"; exit 1; }

# Speed limits by time of day from the tileset's OSM file. Andorra may not have
# any; the file must be there though.
$K exec "$POD" -c traffic -- python3 -c "
import json, urllib.request
speeds = json.load(urllib.request.urlopen('http://localhost:9100/conditional-speeds.json', timeout=5))
print('speeds by time of day:', len(speeds['ways']), 'ways')" || { echo "conditional-speeds is missing"; exit 1; }

# Speed cameras from the same file: Andorra has about ten.
$K exec "$POD" -c traffic -- python3 -c "
import json, urllib.request
layer = json.load(urllib.request.urlopen('http://localhost:9100/enforcement.geojson', timeout=5))
print('speed cameras:', len(layer['features']))
assert layer['features'], 'no speed cameras'" || { echo "enforcement is missing"; exit 1; }

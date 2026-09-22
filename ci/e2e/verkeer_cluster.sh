#!/usr/bin/env bash
# Toetst in het cluster dat de importer de nagemaakte feed in Valhalla heeft gezet:
# de file op de CG-2 maakt "vertrek nu" trager dan dezelfde route zonder live
# verkeer, en de afgesloten straat wordt gemeden.
set -euo pipefail
CLUSTER=$1 NS=$2 RELEASE=$3
K="kubectl --context kind-$CLUSTER -n $NS"
POD=$($K get pod -l app.kubernetes.io/component=valhalla -o name | head -1)

vraag() { $K exec "$POD" -c verkeer -- python3 -c "
import json, sys, urllib.request
r = urllib.request.urlopen(urllib.request.Request('http://localhost:8002/route', sys.argv[1].encode()), timeout=30)
print(json.load(r)['trip']['summary']['time'])" "$1"; }

ROUTE='"locations":[{"lat":42.5361,"lon":1.5828},{"lat":42.5670,"lon":1.5990}],"costing":"auto","date_time":{"type":0}'
echo "wachten op de eerste ronde van de importer"
for _ in $(seq 1 30); do
  edges=$($K exec "$POD" -c verkeer -- python3 -c "
import urllib.request
for regel in urllib.request.urlopen('http://localhost:9100/metrics', timeout=5).read().decode().splitlines():
    if regel.startswith('homemaps_traffic_edges_met_snelheid '): print(int(float(regel.split()[1])))" 2>/dev/null || echo 0)
  [ "${edges:-0}" -gt 0 ] && break
  sleep 10
done
echo "edges met live snelheid: ${edges:-0}"
[ "${edges:-0}" -gt 0 ] || { $K logs "$POD" -c verkeer --tail=40; exit 1; }

live=$(vraag "{$ROUTE}")
zonder=$(vraag "{$ROUTE,\"costing_options\":{\"auto\":{\"speed_types\":[\"freeflow\",\"constrained\",\"predicted\"]}}}")
echo "CG-2 met live verkeer: ${live}s, zonder: ${zonder}s"
python3 -c "import sys; sys.exit(0 if float('$live') > float('$zonder') * 1.5 else 'live verkeer heeft geen effect')"
echo "live verkeer werkt"

# De kaartlaag uit dezelfde ronde: de file, de afsluiting, het ongeval en de
# tijdelijke maximumsnelheid van de nepfeed. De snelheid ligt op de CG-2, één
# rijbaan: één of twee keer (heen, en terug als die over dezelfde way loopt).
soorten=$($K exec "$POD" -c verkeer -- python3 -c "
import json, urllib.request
laag = json.load(urllib.request.urlopen('http://localhost:9100/verkeer.geojson', timeout=5))
print(' '.join(sorted({f['properties']['soort'] for f in laag['features']})))")
echo "kaartlaag: $soorten"
[ "$soorten" = "dicht file ongeval snelheid" ] || { echo "kaartlaag klopt niet"; exit 1; }

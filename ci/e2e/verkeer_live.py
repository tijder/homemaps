"""Bewijst tegen een draaiende Valhalla (Andorra-tileset) dat wijzigingen in
traffic.tar zonder herstart doorwerken: file -> langere reistijd, afsluiting ->
andere route, wissen -> terug bij af.

Gebruik: verkeer_live.py <pad naar traffic.tar> [valhalla-url]
"""

import json
import sys
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "importer" / "src"))
from homemaps_traffic import traffictile as tt
from homemaps_traffic.tarindex import TrafficTar

V = sys.argv[2] if len(sys.argv) > 2 else "http://127.0.0.1:8002"
def post(pad, body):
    req = urllib.request.Request(V + pad, json.dumps(body).encode(), {"Content-Type": "application/json"})
    return json.load(urllib.request.urlopen(req, timeout=30))

def route(a, b, **extra):
    r = post("/route", {"locations": [a, b], "costing": "auto", "units": "kilometers", "date_time": {"type": 0}, **extra})
    t = r["trip"]; return t["summary"]["length"], t["summary"]["time"], t["legs"][0]["shape"]

def edges(shape):
    r = post("/trace_attributes", {"encoded_polyline": shape, "costing": "auto", "shape_match": "edge_walk",
                                   "filters": {"attributes": ["edge.id", "edge.length", "edge.speed", "edge.names"], "action": "include"}})
    return r["edges"]

def toon(naam, a, b, **extra):
    l, t, s = route(a, b, **extra); print(f"  {naam}: {l:.2f} km, {t:.0f} s"); return l, t, s

tar = TrafficTar(sys.argv[1]); tar.wis_alles()
print(f"traffic.tar: {len(tar.tegels)} tegels, {tar.aantal_edges} edges")

print("1) file op de CG-2 (Andorra la Vella -> Pas de la Casa)")
A, B = {"lat": 42.5063, "lon": 1.5218}, {"lat": 42.5425, "lon": 1.7335}
_, t0, shape = toon("zonder verkeer", A, B)
es = edges(shape); ids = [e["id"] for e in es]
print(f"  {len(ids)} edges op de route, vrije snelheid eerste: {es[0]['speed']} km/u")
print("  geschreven/gewist/onbekend:", tar.werk_bij({i: tt.snelheid(10, 60) for i in ids}, set()))
_, t1, _ = toon("alle edges op 10 km/u", A, B)
l, t, _ = toon("zelfde, maar speed_types zonder 'current'", A, B, costing_options={"auto": {"speed_types": ["freeflow", "constrained", "predicted"]}})
tar.werk_bij({}, set(ids))
_, t2, _ = toon("na wissen", A, B)
assert t1 > t0 * 1.5 and abs(t2 - t0) < 1, "live verkeer wordt niet opgepikt"

print("2) afsluiting in de stad")
C, D = {"lat": 42.5075, "lon": 1.5205}, {"lat": 42.5100, "lon": 1.5390}
l0, _, shape = toon("zonder afsluiting", C, D)
es = edges(shape); midden = es[len(es) // 2]
print(f"  sluit edge {midden['id']} ({midden.get('names')}, {midden['length']*1000:.0f} m)")
tar.werk_bij({midden["id"]: tt.afgesloten()}, set())
l1, _, shape1 = toon("met afsluiting", C, D)
assert midden["id"] not in [e["id"] for e in edges(shape1)], "de route gaat nog over de afgesloten edge"
tar.wis_alles(); l2, _, _ = toon("na wissen", C, D)
assert abs(l2 - l0) < 0.01
print("OK: Valhalla ziet wijzigingen in de mmap zonder herstart")

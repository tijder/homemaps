"""Proves against a running Valhalla (Andorra tileset) that changes in
traffic.tar take effect without a restart: jam -> longer travel time, closure ->
different route, clear -> back to square one.

Usage: traffic_live.py <path to traffic.tar> [valhalla-url]
"""

import json
import sys
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "importer" / "src"))
from homemaps_traffic import traffictile as tt
from homemaps_traffic.tarindex import TrafficTar

V = sys.argv[2] if len(sys.argv) > 2 else "http://127.0.0.1:8002"
def post(path, body):
    req = urllib.request.Request(V + path, json.dumps(body).encode(), {"Content-Type": "application/json"})
    return json.load(urllib.request.urlopen(req, timeout=30))

def route(a, b, **extra):
    r = post("/route", {"locations": [a, b], "costing": "auto", "units": "kilometers", "date_time": {"type": 0}, **extra})
    t = r["trip"]; return t["summary"]["length"], t["summary"]["time"], t["legs"][0]["shape"]

def edges(shape):
    r = post("/trace_attributes", {"encoded_polyline": shape, "costing": "auto", "shape_match": "edge_walk",
                                   "filters": {"attributes": ["edge.id", "edge.length", "edge.speed", "edge.names"], "action": "include"}})
    return r["edges"]

def show(name, a, b, **extra):
    l, t, s = route(a, b, **extra); print(f"  {name}: {l:.2f} km, {t:.0f} s"); return l, t, s

tar = TrafficTar(sys.argv[1]); tar.clear_all()
print(f"traffic.tar: {len(tar.tiles)} tiles, {tar.edge_count} edges")

print("1) jam on the CG-2 (Andorra la Vella -> Pas de la Casa)")
A, B = {"lat": 42.5063, "lon": 1.5218}, {"lat": 42.5425, "lon": 1.7335}
_, t0, shape = show("without traffic", A, B)
es = edges(shape); ids = [e["id"] for e in es]
print(f"  {len(ids)} edges on the route, free-flow speed of the first: {es[0]['speed']} km/h")
print("  written/cleared/unknown:", tar.update({i: tt.speed(10, 60) for i in ids}, set()))
_, t1, _ = show("all edges at 10 km/h", A, B)
l, t, _ = show("same, but speed_types without 'current'", A, B, costing_options={"auto": {"speed_types": ["freeflow", "constrained", "predicted"]}})
tar.update({}, set(ids))
_, t2, _ = show("after clearing", A, B)
assert t1 > t0 * 1.5 and abs(t2 - t0) < 1, "live traffic is not picked up"

print("2) closure in town")
C, D = {"lat": 42.5075, "lon": 1.5205}, {"lat": 42.5100, "lon": 1.5390}
l0, _, shape = show("without closure", C, D)
es = edges(shape); middle = es[len(es) // 2]
print(f"  closing edge {middle['id']} ({middle.get('names')}, {middle['length']*1000:.0f} m)")
tar.update({middle["id"]: tt.closed()}, set())
l1, _, shape1 = show("with closure", C, D)
assert middle["id"] not in [e["id"] for e in edges(shape1)], "the route still goes over the closed edge"
tar.clear_all(); l2, _, _ = show("after clearing", C, D)
assert abs(l2 - l0) < 0.01
print("OK: Valhalla sees changes in the mmap without a restart")

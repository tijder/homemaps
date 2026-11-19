---
sidebar_position: 3
title: Live traffic
description: How NDW open data becomes live speeds, closures and warnings in Valhalla and the app.
---

# Live traffic

The traffic importer is a sidecar in the Valhalla pod. Every few minutes it
fetches open data from NDW (the Dutch national road traffic data portal),
writes live speeds and closures straight into Valhalla's `traffic.tar`, and
builds the traffic layer for the app. Valhalla keeps that file open via mmap,
so a new route takes the current jams into account without a restart.

It only knows the Netherlands. Elsewhere, turn it off with
`valhalla.traffic.enabled=false`; the app then hides the traffic layer and the
option.

## What comes from where

| NDW feed | in the app |
|---|---|
| travel times per segment | live speed per road edge: the route avoids jams, and the layer shows slow traffic and jams |
| closures (`carriagewayClosures`, `roadClosed`) | closed edges: the route drives around them; on the map with the cause and until when |
| lane closures | roadworks on the map |
| safety messages (accident, breakdown, object on the road) | points on the map; a spoken warning while driving |
| roadworks planning feed (once an hour) | planned closures of the coming 8 days, for **Depart › Later** |
| temporary maximum speeds | the speed limit while driving, if lower than OpenStreetMap's |
| matrix signs (MSI, every minute) | the overhead signs drawn as shown, and their speed as the limit |
| open bridges | a warning while driving |

From the OSM extract itself (which the Valhalla build puts down), the importer
also derives `maxspeed:conditional` (limits that depend on the time of day)
and the speed cameras and average speed checks; those work in every region.

## Values

```yaml
valhalla:
  traffic:
    enabled: true
    intervalSeconds: 300     # a cycle; the first takes about a minute at full scale
    closures: true
    msiSeconds: 60           # the overhead signs; 0 turns them off
    incidents: true          # accidents, breakdowns, objects on the road
    bridges: true            # bridges that are open right now
    speedLimits: true        # temporary maximum speeds at road works
    planningSeconds: 3600    # closures in the coming days; 0 turns them off
    ndwUrl: https://opendata.ndw.nu
```

## When a feed fails

NDW renames a feed now and then, and is sometimes down. The importer goes on
with what it has:

- Without the travel times a cycle fails. The traffic of the last good cycle
  stays for three cycles (at least 15 minutes) and is then cleared, in
  Valhalla and on the map: Valhalla has no expiry of its own, and an old jam
  would otherwise stay in every route.
- Without the closures feed the closures of the last good fetch stay for the
  same time.
- Every other feed only costs its own part of the map. Turn one off with its
  value above when it stays broken.

## How well does it match

An NDW segment is nearly always just a start and an end point. The importer
lets Valhalla route between them and takes those edges as the segment. At full
scale 96% of the 67,000 segments match, and 77% of the closures; the rest are
points that fell on a parallel road or the other carriageway. Matches are
cached per tileset, because edge ids change with every Valhalla build.

## Terms

The chart and the images contain no NDW data. Whoever runs the importer uses
NDW's open data under NDW's terms
([ndw.nu/copyright](https://www.ndw.nu/copyright)).

## Metrics

The importer exposes Prometheus metrics on port 9100 (cycle time, matched
segments, closures, and per feed when it last arrived and how often it
failed); `monitoring.serviceMonitor.enabled` scrapes them.
`monitoring.prometheusRule.enabled` alerts when no cycle has finished for
half an hour (`maxAgeSeconds`) and when a single feed has not arrived for
three hours (`feedMaxAgeSeconds`). The latter is the only sign of a feed NDW
renamed, because the importer runs on without it.

The sidecar has a liveness probe on `/healthz`: it restarts when its loop
has stopped running, not when NDW is down.

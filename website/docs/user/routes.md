---
sidebar_position: 3
title: Routes
description: Plan a route for car, bike or foot, with stops, alternatives, an elevation profile and sharing.
---

# Routes

Tap **Directions** on a place, or the route button next to the search field,
and the route panel opens with **From**, **To** and, if you want, **Via**.
**From** starts as your location.

## Means of transport

**Car**, **Bike** or **Walk**. Routes come from your own Valhalla server. For
the car, **Options** has:

- **Use live traffic**: take the current jams and closures into account. Only
  where the server has a traffic source, see [Live traffic](../admin/traffic.md).
- **Avoid motorways**, **Avoid toll roads**, **Avoid ferries**.

Cycling routes take slopes into account when the server has elevation data.

## Stops

**Add stop** adds a via point; drag the handles to change the order, or tap
**Remove**. **Swap start and destination** turns the route around.

**Along the route** finds fuel, charging, a supermarket or food within a
kilometre of the route, sorted by the detour. Tap one and it becomes a stop.

## Alternatives

Without stops Valhalla offers up to two alternatives next to the **Fastest**
route. Tap one on the map or in the list to choose it. Each shows the
duration, the distance, and whether it has a toll road or a ferry.

## Departure

**Depart › Now** uses the live traffic of this moment. **Later…** picks a
time; the route then warns about planned closures in that window, from the
roadworks planning feed.

## Directions and elevation

**Directions** lists every manoeuvre with its distance. **Elevation profile**
shows the climb and descent along the route (and the total as `+120 m / -80 m`);
touch the graph to see the point on the map.

## Share a route

Every route is also a link: the web app opens
`https://maps.example.org/?to=52.17,5.60` with directions to that point from
your location, and `&from=52.18,5.70` fixes the start too. Paste it in a
message and the other person gets the same route on your server.

`geo:` links from other apps open HomeMaps on Android.

## Start

**Start** begins the [navigation](navigation.md). On the computer there is a
simulation instead, for trying things out: add `?simulate=52.186,5.7035` to
the address of the web app and a fake GPS drives the route.

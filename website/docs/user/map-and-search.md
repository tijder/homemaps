---
sidebar_position: 2
title: Map and search
description: Map styles, day and night, layers, and how to find places.
---

# Map and search

## The map

The map is OpenStreetMap, rendered by your own server. There are three styles,
under **Settings › Map**:

| style | what it is |
|---|---|
| **Map** | the full map with a day and a night version |
| **Light** | a quiet, light map |
| **Dark** | a dark map |

With **Map**, **Day and night** decides when the night version is used:
automatically with the dark mode of your device, always day or always night.

Drag with one finger to move, pinch to zoom, rotate with two fingers. The
compass button puts north back on top. **My location** centres the map on
you; tap it again and the map turns with you.

### Layers

- **Traffic**: closures, roadworks and traffic jams from the live traffic
  feed. Tap one for the details: the cause, the delay, and until when. Only in
  regions where the server has a traffic source, see [Live traffic](../admin/traffic.md).
- **Speed cameras**: speed cameras, average speed checks and red light cameras
  from OpenStreetMap. While driving these also appear next to the speed limit.

## Search

Type in the search field at the top:

- a place or street, optionally with a house number (`Kerkstraat 12 Utrecht`)
- a Dutch postcode with house number (`3511 AB 12`)
- a category near where you are, such as `supermarket`
- coordinates, as `52.09, 5.12`

Results come from your own Photon server, so nothing is sent elsewhere. Tap a
result to see it on the map. The card of a place has **Route**, and **Set as
home** or **Set as work**.

The search looks around what the map shows, not around where you are: pan to
another town first and its streets come up on top. While a search is under
way a bar runs below the field; **Nothing found** and a search that failed
each get a line of their own, and a tap on the latter tries again.

Long-press anywhere on the map (right-click on a computer) for a point that
is not an address: **Directions from here**, **Directions to here** or **Add
as stop**.

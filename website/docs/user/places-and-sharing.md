---
sidebar_position: 6
title: Places and sharing
description: Home, work and recent places, your family on the map through Dawarich, and sending your location to your own server.
---

# Places and sharing

## Places

**Settings › Places** shows **Home**, **Work** and your **Recent places**.
Set home and work on the card of a place you found; they also appear in the
car. **Clear** empties the recent places. Everything is stored on the phone,
nothing on the server.

## Dawarich

[Dawarich](https://dawarich.app) is a self-hosted location history. Connect
HomeMaps to your own Dawarich under **Settings › Dawarich** and you can:

- **Share location with family**: for 1, 6, 12 or 24 hours, or until you turn
  it off. Your family is a Dawarich feature; create one on its website.
- **Family members on the map**: see where they are, with when the position
  was taken and their battery. **Follow** keeps the map on one of them.
- **Share location while navigating**: your trips are recorded in Dawarich.

Sign in with your email and password (with a two-factor code if you use one),
with an API key from Dawarich's settings, or through the Dawarich website
(also for OIDC such as Keycloak or Authentik).

In the browser Dawarich has to allow cross-origin requests to `/api/v1`; if
the web app cannot reach it, add CORS headers in your reverse proxy or use the
phone app.

## Location sharing

**Settings › Location sharing** sends your position to a server of your own
while you navigate, and only then. Ready-made formats:

| format | for |
|---|---|
| OwnTracks | OwnTracks Recorder and everything that speaks it |
| Reitti | Reitti (OwnTracks compatible) |
| Overland | Overland: batches of points as GeoJSON |
| Traccar | Traccar, OsmAnd protocol |
| GeoPulse | the Colota format |
| Nextcloud PhoneTrack | PhoneTrack |
| Dawarich | the Dawarich API, with heading, battery and transport mode |
| Custom | your own field names and fixed fields |

Set the address, the method (POST or GET), authentication (none, username
and password, or a token), and how often: every so many seconds, or after so
many metres. **Test connection** sends one point. Points that could not be
sent wait in a queue and go out later.

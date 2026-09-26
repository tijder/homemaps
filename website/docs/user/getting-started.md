---
sidebar_position: 1
title: Getting started
description: Open the web app, install the Android or iOS app and connect it to your server.
---

# Getting started

HomeMaps is a map and route planner that runs on a server of your own. The same
app exists three times: as a web app on that server, as an Android app and as an
iOS app. All three do the same: map, search, routes and navigation, in English
and Dutch (the app follows the language of your device).

## The web app

The web app lives on the server itself, for example `https://maps.example.org`.
Open that address in a browser and you are done: the web app knows its own
server. It works on a phone as well as on a computer, and you can add it to
your home screen.

Navigation with voice works in the browser too, but the browser has to stay in
the foreground. For navigation on the road, the phone apps are the better choice.

## Android

Download the APK from the [latest release](https://github.com/tijder/homemaps/releases/latest)
and install it. Android asks once whether it may install apps from this source.
Updates are a new APK over the old one; your settings stay.

The app is also available for Android Auto, see [In the car](car.md).

## iPhone and iPad

The iOS app is distributed through TestFlight. Ask whoever runs your server for
the invitation link, or see whether the [download buttons](/) on this site
have one. Install TestFlight from the App Store, open the link and install
HomeMaps.

## First start

On a phone the app asks one thing on its first start: the address of your
HomeMaps server, for example `maps.example.org`. It checks right away whether
the map, the search and the routing answer there. As soon as that works, the
address is saved and you are taken to the map.

The two steps after that are optional and can be skipped:

- **Dawarich**: sign in to your own Dawarich to see your family on the map and
  to keep your trips, see [Places and sharing](places-and-sharing.md).
- **Location sharing**: send your position to a service of your own while you
  navigate, for example OwnTracks or Traccar.

Both can be set up later under **Settings**.

## Permissions

The app asks for your location when you tap **My location** or start
navigating. Without it the map still works, but there is no blue dot and no
navigation. On Android the app keeps following you while the screen is off,
with a notification that says it is doing so; that stops as soon as you stop
the navigation.

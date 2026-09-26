---
sidebar_position: 6
title: Plekken en delen
description: Thuis, werk en recente plekken, je familie op de kaart via Dawarich, en je locatie naar je eigen server sturen.
---

# Plekken en delen

## Plekken

**Instellingen › Plekken** toont **Thuis**, **Werk** en je **Recente plekken**.
Thuis en werk stel je in op het kaartje van een gevonden plek; ze staan ook in
de auto. **Wissen** maakt de recente plekken leeg. Alles staat op de telefoon,
niets op de server.

## Dawarich

[Dawarich](https://dawarich.app) is een zelf gehoste locatiegeschiedenis.
Koppel HomeMaps aan je eigen Dawarich onder **Instellingen › Dawarich** en je kunt:

- **Locatie delen met familie**: 1, 6, 12 of 24 uur, of tot je het uitzet. Je
  familie is een functie van Dawarich; maak er een op de website.
- **Familieleden op de kaart**: zie waar ze zijn, met wanneer de positie is
  genomen en hun batterij. **Volgen** houdt de kaart op een van hen.
- **Locatie delen tijdens navigeren**: je ritten worden in Dawarich vastgelegd.

Log in met je e-mail en wachtwoord (met een code voor tweestapsverificatie als
je die gebruikt), met een API-sleutel uit de instellingen van Dawarich, of via
de Dawarich-website (ook voor OIDC zoals Keycloak of Authentik).

In de browser moet Dawarich cross-origin-verzoeken naar `/api/v1` toestaan;
kan de web-app hem niet bereiken, voeg dan CORS-headers toe in je reverse proxy
of gebruik de telefoon-app.

## Locatie delen

**Instellingen › Locatie delen** stuurt je positie naar een eigen server
terwijl je navigeert, en alleen dan. Kant-en-klare formaten:

| formaat | voor |
|---|---|
| OwnTracks | OwnTracks Recorder en alles wat dat spreekt |
| Reitti | Reitti (OwnTracks-compatibel) |
| Overland | Overland: punten in batches als GeoJSON |
| Traccar | Traccar, OsmAnd-protocol |
| GeoPulse | het Colota-formaat |
| Nextcloud PhoneTrack | PhoneTrack |
| Dawarich | de Dawarich-API, met richting, batterij en vervoer |
| Eigen server | je eigen veldnamen en vaste velden |

Stel het adres in, de methode (POST of GET), het inloggen (geen,
gebruikersnaam en wachtwoord, of een token), en hoe vaak: elke zoveel
seconden, of na zoveel meter. **Verbinding testen** stuurt één punt. Punten die
niet verstuurd konden worden wachten in een wachtrij en gaan later mee.

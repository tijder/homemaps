---
sidebar_position: 3
title: Routes
description: Plan een route voor auto, fiets of te voet, met tussenpunten, alternatieven, een hoogteprofiel en delen.
---

# Routes

Tik op **Route** bij een plek, of op de routeknop naast het zoekveld, en het
routepaneel opent met **Van**, **Naar** en, als je wilt, **Via**. **Van**
begint als jouw locatie.

## Vervoermiddel

**Auto**, **Fiets** of **Lopen**. Routes komen van je eigen Valhalla-server.
Voor de auto heeft **Opties**:

- **Actueel verkeer meenemen**: rekening houden met de files en afsluitingen
  van nu. Alleen waar de server een verkeersbron heeft, zie
  [Actueel verkeer](../admin/traffic.md).
- **Snelwegen vermijden**, **Tolwegen vermijden**, **Veerponten vermijden**.

Fietsroutes houden rekening met hellingen als de server hoogtegegevens heeft.

## Tussenpunten

**Tussenpunt toevoegen** voegt een via-punt toe; sleep aan de handvatten om de
volgorde te wijzigen, of tik op **Verwijderen**. **Heen en terug omdraaien**
keert de route om.

**Langs de route** vindt tanken, laden, een supermarkt of eten binnen een
kilometer van de route, gesorteerd op de omweg. Tik erop en het wordt een
tussenpunt.

## Alternatieven

Zonder tussenpunten biedt Valhalla tot twee alternatieven naast de **Snelste**
route. Tik erop op de kaart of in de lijst om te kiezen. Elk toont de duur, de
afstand, en of er tol of een veerpont in zit.

## Vertrek

**Vertrek › Nu** gebruikt het actuele verkeer van dit moment. **Later…** kiest
een tijd; de route waarschuwt dan voor geplande afsluitingen in dat venster,
uit de planning van wegwerkzaamheden.

## Routebeschrijving en hoogte

**Routebeschrijving** somt elke manoeuvre op met de afstand. **Hoogteprofiel**
toont het klimmen en dalen langs de route (en het totaal als `+120 m / -80 m`);
raak de grafiek aan om het punt op de kaart te zien.

## Een route delen

Elke route is ook een link: de web-app opent
`https://maps.example.org/?to=52.17,5.60` met een route naar dat punt vanaf je
locatie, en `&from=52.18,5.70` legt ook het begin vast. Plak hem in een
bericht en de ander krijgt dezelfde route op jouw server.

`geo:`-links uit andere apps openen HomeMaps op Android.

## Start

**Start** begint de [navigatie](navigation.md). Op de computer is er in plaats
daarvan een simulatie, om dingen uit te proberen: zet `?simulate=52.186,5.7035`
achter het adres van de web-app en een nep-gps rijdt de route.

---
sidebar_position: 1
title: Aan de slag
description: Open de web-app, installeer de Android- of iOS-app en koppel hem aan je server.
---

# Aan de slag

HomeMaps is een kaart en routeplanner die op een eigen server draait. Dezelfde
app bestaat drie keer: als web-app op die server, als Android-app en als
iOS-app. Alle drie doen hetzelfde: kaart, zoeken, routes en navigatie, in het
Nederlands en Engels (de app volgt de taal van je apparaat).

## De web-app

De web-app staat op de server zelf, bijvoorbeeld `https://maps.example.org`.
Open dat adres in een browser en je bent klaar: de web-app kent zijn eigen
server. Hij werkt op een telefoon en op een computer, en je kunt hem aan je
beginscherm toevoegen.

Navigeren met stem werkt ook in de browser, maar dan moet de browser op de
voorgrond blijven. Voor navigatie op de weg zijn de telefoon-apps de betere keus.

## Android

Download de APK van de [laatste release](https://github.com/tijder/homemaps/releases/latest)
en installeer hem. Android vraagt één keer of het apps van deze bron mag
installeren. Een update is een nieuwe APK over de oude heen; je instellingen blijven.

De app is er ook voor Android Auto, zie [In de auto](car.md).

## iPhone en iPad

De iOS-app wordt via TestFlight verspreid. Vraag de beheerder van je server om
de uitnodigingslink, of kijk of de [downloadknoppen](/) op deze site er een
hebben. Installeer TestFlight uit de App Store, open de link en installeer HomeMaps.

## Eerste start

Op een telefoon vraagt de app bij de eerste start één ding: het adres van je
HomeMaps-server, bijvoorbeeld `maps.example.org`. Hij controleert meteen of de
kaart, het zoeken en de routes daar antwoorden. Zodra dat werkt, wordt het
adres opgeslagen en ga je naar de kaart.

De twee stappen daarna zijn optioneel en kun je overslaan:

- **Dawarich**: log in bij je eigen Dawarich om je familie op de kaart te zien
  en je ritten bij te houden, zie [Plekken en delen](places-and-sharing.md).
- **Locatie delen**: stuur je positie tijdens het navigeren naar een eigen
  dienst, bijvoorbeeld OwnTracks of Traccar.

Beide kun je later instellen onder **Instellingen**.

## Toestemmingen

De app vraagt om je locatie als je op **Mijn locatie** tikt of gaat navigeren.
Zonder werkt de kaart gewoon, maar is er geen blauwe stip en geen navigatie. Op
Android blijft de app je volgen met het scherm uit, met een melding die dat
zegt; dat stopt zodra je de navigatie stopt.

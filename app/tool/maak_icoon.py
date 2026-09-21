"""Tekent het app-icoon: een kaartpin met een huisje erin, op een blauw vlak met een
gestippelde route. Alles is code, zodat kleur en vorm aan te passen zijn zonder
tekenprogramma.

    python3 tool/maak_icoon.py            # schrijft assets/icon/*.png
    dart run flutter_launcher_icons       # maakt er Android- en web-iconen van

Vereist Pillow.
"""

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

MAAT = 1024
SCHAAL = 4  # groter tekenen en verkleinen geeft gladde randen
BLAUW_LICHT, BLAUW_DONKER = (30, 118, 210), (13, 71, 161)
WIT = (255, 255, 255, 255)
UIT = Path(__file__).resolve().parent.parent / "assets" / "icon"


def verloop(maat):
    """Diagonaal verloop van licht (linksboven) naar donker (rechtsonder)."""
    beeld = Image.new("RGB", (maat, maat))
    pixels = beeld.load()
    for y in range(maat):
        for x in range(maat):
            t = (x + y) / (2 * maat)
            pixels[x, y] = tuple(
                round(a + (b - a) * t) for a, b in zip(BLAUW_LICHT, BLAUW_DONKER, strict=True)
            )
    return beeld


def route(beeld, maat):
    """Een gestippelde S-bocht achter de pin langs: daar komt 'maps' vandaan. Op een
    eigen laag getekend en in één keer doorschijnend gemaakt, zodat overlappende
    stippen niet feller worden."""
    laag = Image.new("RGBA", beeld.size, (0, 0, 0, 0))
    teken = ImageDraw.Draw(laag)
    straal = maat * 0.02
    for stap in range(0, 17):
        t = stap / 16
        x = maat * (0.11 + 0.78 * t)
        y = maat * (0.80 - 0.13 * math.sin(t * math.pi * 2) - 0.10 * t)
        teken.ellipse((x - straal, y - straal, x + straal, y + straal), fill=WIT)
    laag.putalpha(laag.split()[3].point(lambda a: a * 0.6))
    beeld.alpha_composite(laag)


def pin(teken, maat, cx, cy, hoogte):
    """De druppelvorm: een cirkel met een punt eronder. (cx, cy) is de punt."""
    straal = hoogte * 0.36
    midden_y = cy - hoogte + straal
    teken.ellipse((cx - straal, midden_y - straal, cx + straal, midden_y + straal), fill=WIT)
    # De raaklijnen van de punt aan de cirkel.
    afstand = cy - midden_y
    hoek = math.acos(straal / afstand)
    links = (cx - straal * math.sin(hoek), midden_y + straal * math.cos(hoek))
    rechts = (cx + straal * math.sin(hoek), midden_y + straal * math.cos(hoek))
    teken.polygon([links, rechts, (cx, cy)], fill=WIT)
    return midden_y, straal


def huis(teken, cx, cy, grootte, kleur):
    """Een huisje: dak, gevel en een deur, gecentreerd op (cx, cy)."""
    breed, hoog = grootte, grootte * 0.92
    dak = hoog * 0.48
    boven, onder = cy - hoog / 2, cy + hoog / 2
    teken.polygon(
        [(cx, boven), (cx + breed * 0.60, boven + dak), (cx - breed * 0.60, boven + dak)],
        fill=kleur,
    )
    teken.rectangle((cx - breed * 0.42, boven + dak * 0.86, cx + breed * 0.42, onder), fill=kleur)
    deur_b, deur_h = breed * 0.13, hoog * 0.30
    teken.rectangle((cx - deur_b, onder - deur_h, cx + deur_b, onder + 1), fill=WIT)


def teken_voorgrond(maat, pin_hoogte):
    beeld = Image.new("RGBA", (maat, maat), (0, 0, 0, 0))
    teken = ImageDraw.Draw(beeld)
    cx, punt_y = maat / 2, maat / 2 + pin_hoogte / 2
    midden_y, straal = pin(teken, maat, cx, punt_y, pin_hoogte)
    huis(teken, cx, midden_y, straal * 1.05, BLAUW_DONKER + (255,))
    return beeld


def schaduw(voorgrond, maat):
    alfa = voorgrond.split()[3].filter(ImageFilter.GaussianBlur(maat * 0.018))
    zwart = Image.new("RGBA", voorgrond.size, (0, 0, 0, 0))
    zwart.putalpha(alfa.point(lambda a: a * 0.35))
    verschoven = Image.new("RGBA", voorgrond.size, (0, 0, 0, 0))
    verschoven.paste(zwart, (0, round(maat * 0.015)), zwart)
    return verschoven


def main():
    UIT.mkdir(parents=True, exist_ok=True)
    groot = MAAT * SCHAAL

    # Het volledige icoon (web, favicon, oudere Android): afgeronde hoeken.
    achtergrond = verloop(groot).convert("RGBA")
    route(achtergrond, groot)
    pin_laag = teken_voorgrond(groot, groot * 0.62)
    achtergrond.alpha_composite(schaduw(pin_laag, groot))
    achtergrond.alpha_composite(pin_laag)
    masker = Image.new("L", (groot, groot), 0)
    ImageDraw.Draw(masker).rounded_rectangle((0, 0, groot, groot), radius=groot * 0.22, fill=255)
    achtergrond.putalpha(masker)
    achtergrond.resize((MAAT, MAAT), Image.LANCZOS).save(UIT / "icon.png")

    # Adaptief icoon (Android 8+): het systeem snijdt zelf een vorm uit, dus de
    # achtergrond loopt door tot de rand en de pin blijft binnen de veilige 66%.
    vlak = verloop(groot).convert("RGBA")
    route(vlak, groot)
    vlak.resize((MAAT, MAAT), Image.LANCZOS).save(UIT / "icon-achtergrond.png")
    voorgrond = teken_voorgrond(groot, groot * 0.44)
    samen = Image.new("RGBA", (groot, groot), (0, 0, 0, 0))
    samen.alpha_composite(schaduw(voorgrond, groot))
    samen.alpha_composite(voorgrond)
    samen.resize((MAAT, MAAT), Image.LANCZOS).save(UIT / "icon-voorgrond.png")
    for naam in ("icon", "icon-achtergrond", "icon-voorgrond"):
        print(UIT / f"{naam}.png")


if __name__ == "__main__":
    main()

"""Schermafdrukken voor de App Store, van de web-app tegen de chart: dezelfde
Flutter-UI als op iOS, in de maten die App Store Connect vraagt.

    python3 ci/e2e/schermafdrukken.py <url van de web-app> <start lat,lon> <plaatsnaam>

Zoekt <plaatsnaam> op, plant er een route heen en navigeert een stuk.

Schrijft ci/e2e/uitvoer/appstore/<taal>/<toestel>/NN-naam.png, voor nl en en en
voor iPhone 6.7" (1290x2796) en iPad 12.9" (2048x2732). ci/appstore/upload.py zet
ze in App Store Connect. Net als ci/e2e/app_browser.py stuurt dit de app via
?simulatie= en leest het de stand van window.homemaps.
"""

import asyncio
import json
import re
import shutil
import sys
from pathlib import Path

from playwright.async_api import async_playwright

UIT = Path(__file__).parent / "uitvoer" / "appstore"
# Punten maal schaal = de pixels die Apple voor dit weergavetype verwacht.
TOESTELLEN = {
    "iphone": {"viewport": {"width": 430, "height": 932}, "device_scale_factor": 3},
    "ipad": {"viewport": {"width": 1024, "height": 1366}, "device_scale_factor": 2},
}
TALEN = {"nl": "nl-NL", "en": "en-US"}
# Knoppen op naam, zoals in app/lib/l10n/app_*.arb.
MIJN_LOCATIE = {"nl": "Mijn locatie", "en": "My location"}
ROUTE = {"nl": "Route", "en": "Directions"}


async def stand(pagina):
    tekst = await pagina.evaluate("() => window.homemaps || null")
    return json.loads(tekst) if tekst else {}


async def wacht(pagina, beschrijving, voorwaarde, seconden=60):
    huidig = {}
    for _ in range(seconden * 2):
        huidig = await stand(pagina)
        if voorwaarde(huidig):
            return huidig
        await pagina.wait_for_timeout(500)
    raise AssertionError(f"{beschrijving}: bleef uit (laatste stand {huidig})")


async def rustig(pagina):
    """Tot de kaarttegels binnen zijn en animaties uit."""
    await pagina.wait_for_load_state("networkidle")
    await pagina.wait_for_timeout(2500)


async def reeks(browser, basis, start, doel, taal, toestel, uit):
    uit.mkdir(parents=True, exist_ok=True)
    context = await browser.new_context(
        **TOESTELLEN[toestel], locale=TALEN[taal], is_mobile=True, has_touch=True
    )
    pagina = await context.new_page()
    console = []
    pagina.on("console", lambda bericht: console.append(f"[{bericht.type}] {bericht.text}"))
    pagina.on("pageerror", lambda fout: console.append(f"[pageerror] {fout}"))
    async def open_():
        # kubectl port-forward laat soms een verbinding vallen; dan laadt de app
        # niet en blijft de pagina wit. Opnieuw laden helpt.
        for poging in range(3):
            await pagina.goto(f"{basis}/?simulatie={start}&snelheid=15")
            try:
                await wacht(pagina, "locatie aan", lambda s: s.get("locatie") == "aan", seconden=45)
                break
            except AssertionError:
                if poging == 2:
                    raise
        # De toegankelijkheidsboom aan: knoppen op naam, niet op pixels.
        await pagina.locator("flt-semantics-placeholder").dispatch_event("click")

    try:
        # 1. De kaart rond je eigen locatie. Weg met de muis, anders staat de
        # tooltip van de knop erop.
        await open_()
        await pagina.get_by_role("button", name=MIJN_LOCATIE[taal], exact=True).click(timeout=15000)
        await pagina.mouse.move(1, 1)
        await rustig(pagina)
        await pagina.screenshot(path=uit / "1-kaart.png")

        # 2. Zoeken, met de suggesties van Photon. Opnieuw geladen: na de klik op
        # "Mijn locatie" krijgt het zoekveld de focus niet meer.
        await open_()
        await pagina.get_by_role("textbox").first.click()
        await pagina.wait_for_timeout(1500)
        await pagina.keyboard.type(doel, delay=80)
        resultaat = pagina.get_by_role("button", name=re.compile(rf"^{re.escape(doel)}\b")).first
        await resultaat.wait_for(timeout=30000)
        await rustig(pagina)
        await pagina.screenshot(path=uit / "2-zoeken.png")

        # 3. De route, met de keuzes en het hoogteprofiel.
        await resultaat.click()
        await pagina.get_by_role("button", name=ROUTE[taal], exact=True).click(timeout=15000)
        await wacht(pagina, "route berekend", lambda s: s.get("routes", 0) > 0)
        await rustig(pagina)
        await pagina.screenshot(path=uit / "3-route.png")

        # 4. Onderweg: de volgende afslag en de rest van de rit.
        await pagina.get_by_role("button", name="Start", exact=True).click(timeout=15000)
        eerste = await wacht(pagina, "navigatie loopt", lambda s: s.get("navigeert") and s.get("restMeters"))
        await wacht(
            pagina,
            "een eind onderweg",
            lambda s: s.get("restMeters") is not None and s["restMeters"] < eerste["restMeters"] - 300,
        )
        await pagina.wait_for_timeout(2500)
        await pagina.screenshot(path=uit / "4-navigatie.png")
    except Exception:
        await pagina.screenshot(path=UIT / f"fout-{taal}-{toestel}.png")
        (UIT / f"fout-{taal}-{toestel}.txt").write_text("\n".join(console))
        raise
    finally:
        await context.close()


async def main(basis, start, doel):
    shutil.rmtree(UIT, ignore_errors=True)
    async with async_playwright() as p:
        browser = await p.chromium.launch(
            args=["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader"]
        )
        try:
            for taal in TALEN:
                for toestel in TOESTELLEN:
                    await reeks(browser, basis, start, doel, taal, toestel, UIT / taal / toestel)
                    print(f"  ok: {taal} {toestel}")
        finally:
            await browser.close()
    print(f"schermafdrukken in {UIT}")


if __name__ == "__main__":
    asyncio.run(main(*sys.argv[1:4]))

"""De app in een echte browser tegen de chart: route plannen, navigeren met een
nagemaakte GPS, stoppen. Wat unittests niet zien -- de kaart, de knoppen, de
proxy naar Valhalla -- komt hier samen.

    python3 ci/e2e/app_browser.py <url van de web-app> <start lat,lon> <doel lat,lon>

De app publiceert met ?simulatie= zijn stand op window.homemaps (zie
lib/utils/testhaak_web.dart); knoppen worden via de toegankelijkheidsboom
gevonden, niet op pixels. Bij een fout staan schermafdrukken in
ci/e2e/uitvoer/.
"""

import asyncio
import json
import sys
from pathlib import Path

from playwright.async_api import TimeoutError as PlaywrightTimeout
from playwright.async_api import async_playwright

UIT = Path(__file__).parent / "uitvoer"


async def stand(pagina):
    tekst = await pagina.evaluate("() => window.homemaps || null")
    return json.loads(tekst) if tekst else {}


async def wacht(pagina, beschrijving, voorwaarde, seconden=60):
    for _ in range(seconden * 2):
        huidig = await stand(pagina)
        if voorwaarde(huidig):
            print(f"  ok: {beschrijving}")
            return huidig
        await pagina.wait_for_timeout(500)
    raise AssertionError(f"{beschrijving}: bleef uit (laatste stand {huidig})")


async def main(basis: str, start: str, doel: str) -> None:
    UIT.mkdir(exist_ok=True)
    async with async_playwright() as p:
        browser = await p.chromium.launch(
            args=["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader"]
        )
        pagina = await browser.new_page(viewport={"width": 1400, "height": 850}, locale="nl-NL")
        fouten = []
        pagina.on("pageerror", lambda fout: fouten.append(str(fout)))
        try:
            await pagina.goto(f"{basis}/?simulatie={start}&snelheid=25&naar={doel}")
            await wacht(pagina, "locatie aan", lambda s: s.get("locatie") == "aan")
            planning = await wacht(pagina, "route berekend", lambda s: s.get("routes", 0) > 0)
            print(f"  {planning['routes']} route(s)")
            await pagina.screenshot(path=UIT / "1-route.png")

            # De toegankelijkheidsboom aan, dan de knop op naam.
            await pagina.locator("flt-semantics-placeholder").dispatch_event("click")
            await pagina.get_by_role("button", name="Start").click(timeout=15000)
            eerste = await wacht(pagina, "navigatie loopt", lambda s: s.get("navigeert") and s.get("restMeters"))
            print(f"  volgende: {eerste['volgende']!r}, nog {eerste['restMeters']} m")
            later = await wacht(
                pagina,
                "de nagemaakte GPS rijdt op de route",
                lambda s: s.get("restMeters") is not None
                and s["restMeters"] < eerste["restMeters"] - 100
                and not s.get("vanRoute"),
            )
            print(f"  nog {later['restMeters']} m")
            await pagina.screenshot(path=UIT / "2-navigatie.png")

            await pagina.get_by_role("button", name="Stop").click(timeout=15000)
            await wacht(pagina, "gestopt", lambda s: not s.get("navigeert"))
            if fouten:
                raise AssertionError(f"fouten in de pagina: {fouten}")
        except (AssertionError, PlaywrightTimeout):
            await pagina.screenshot(path=UIT / "fout.png")
            raise
        finally:
            await browser.close()
    print("app in de browser: in orde")


if __name__ == "__main__":
    asyncio.run(main(*sys.argv[1:4]))

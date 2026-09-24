"""Screenshots for the App Store, of the web app against the chart: the same
Flutter UI as on iOS, in the sizes App Store Connect asks for.

    python3 ci/e2e/screenshots.py <url of the web app> <start lat,lon> <place name>

Searches for <place name>, plans a route there and navigates a stretch.

Writes ci/e2e/output/appstore/<lang>/<device>/NN-name.png, for nl and en and
for iPhone 6.7" (1290x2796) and iPad 12.9" (2048x2732). ci/appstore/upload.py puts
them in App Store Connect. Like ci/e2e/app_browser.py, this drives the app via
?simulate= and reads its state from window.homemaps.
"""

import asyncio
import json
import re
import shutil
import sys
from pathlib import Path

from playwright.async_api import async_playwright

OUT = Path(__file__).parent / "output" / "appstore"
# Points times scale = the pixels Apple expects for this display type.
DEVICES = {
    "iphone": {"viewport": {"width": 430, "height": 932}, "device_scale_factor": 3},
    "ipad": {"viewport": {"width": 1024, "height": 1366}, "device_scale_factor": 2},
}
LANGUAGES = {"nl": "nl-NL", "en": "en-US"}
# Buttons by name, as in app/lib/l10n/app_*.arb.
MY_LOCATION = {"nl": "Mijn locatie", "en": "My location"}
ROUTE = {"nl": "Route", "en": "Directions"}


async def state(page):
    text = await page.evaluate("() => window.homemaps || null")
    return json.loads(text) if text else {}


async def wait(page, description, condition, seconds=60):
    current = {}
    for _ in range(seconds * 2):
        current = await state(page)
        if condition(current):
            return current
        await page.wait_for_timeout(500)
    raise AssertionError(f"{description}: never happened (last state {current})")


async def settled(page):
    """Until the map tiles are in and animations are done."""
    await page.wait_for_load_state("networkidle")
    await page.wait_for_timeout(2500)


async def series(browser, base, start, destination, lang, device, out):
    out.mkdir(parents=True, exist_ok=True)
    context = await browser.new_context(
        **DEVICES[device], locale=LANGUAGES[lang], is_mobile=True, has_touch=True
    )
    page = await context.new_page()
    console = []
    page.on("console", lambda message: console.append(f"[{message.type}] {message.text}"))
    page.on("pageerror", lambda error: console.append(f"[pageerror] {error}"))
    async def open_():
        # kubectl port-forward sometimes drops a connection; then the app doesn't
        # load and the page stays white. Reloading helps.
        for attempt in range(3):
            await page.goto(f"{base}/?simulate={start}&speed=15")
            try:
                await wait(page, "location on", lambda s: s.get("location") == "enabled", seconds=45)
                break
            except AssertionError:
                if attempt == 2:
                    raise
        # Accessibility tree on: buttons by name, not by pixels.
        await page.locator("flt-semantics-placeholder").dispatch_event("click")

    try:
        # 1. The map around your own location. Mouse out of the way, otherwise the
        # button's tooltip shows up on it.
        await open_()
        await page.get_by_role("button", name=MY_LOCATION[lang], exact=True).click(timeout=15000)
        await page.mouse.move(1, 1)
        await settled(page)
        await page.screenshot(path=out / "1-map.png")

        # 2. Search, with Photon's suggestions. Reloaded: after the click on
        # "My location" the search field no longer gets focus.
        await open_()
        await page.get_by_role("textbox").first.click()
        await page.wait_for_timeout(1500)
        await page.keyboard.type(destination, delay=80)
        result = page.get_by_role("button", name=re.compile(rf"^{re.escape(destination)}\b")).first
        await result.wait_for(timeout=30000)
        await settled(page)
        await page.screenshot(path=out / "2-search.png")

        # 3. The route, with the alternatives and the elevation profile.
        await result.click()
        await page.get_by_role("button", name=ROUTE[lang], exact=True).click(timeout=15000)
        await wait(page, "route computed", lambda s: s.get("routes", 0) > 0)
        await settled(page)
        await page.screenshot(path=out / "3-route.png")

        # 4. On the way: the next turn and the rest of the trip.
        await page.get_by_role("button", name="Start", exact=True).click(timeout=15000)
        first = await wait(page, "navigation running", lambda s: s.get("navigating") and s.get("remainingMeters"))
        await wait(
            page,
            "some way along",
            lambda s: s.get("remainingMeters") is not None and s["remainingMeters"] < first["remainingMeters"] - 300,
        )
        await page.wait_for_timeout(2500)
        await page.screenshot(path=out / "4-navigation.png")
    except Exception:
        await page.screenshot(path=OUT / f"error-{lang}-{device}.png")
        (OUT / f"error-{lang}-{device}.txt").write_text("\n".join(console))
        raise
    finally:
        await context.close()


async def main(base, start, destination):
    shutil.rmtree(OUT, ignore_errors=True)
    async with async_playwright() as p:
        browser = await p.chromium.launch(
            args=["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader"]
        )
        try:
            for lang in LANGUAGES:
                for device in DEVICES:
                    await series(browser, base, start, destination, lang, device, OUT / lang / device)
                    print(f"  ok: {lang} {device}")
        finally:
            await browser.close()
    print(f"screenshots in {OUT}")


if __name__ == "__main__":
    asyncio.run(main(*sys.argv[1:4]))

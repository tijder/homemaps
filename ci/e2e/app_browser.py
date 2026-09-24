"""The app in a real browser against the chart: plan a route, navigate with a
fake GPS, stop. What unit tests don't see -- the map, the buttons, the
proxy to Valhalla -- comes together here.

    python3 ci/e2e/app_browser.py <url of the web app> <start lat,lon> <destination lat,lon>

With ?simulate= the app publishes its state on window.homemaps (see
lib/utils/test_hook_web.dart); buttons are found through the accessibility tree,
not by pixels. On an error, screenshots are in
ci/e2e/output/.
"""

import asyncio
import json
import sys
from pathlib import Path

from playwright.async_api import TimeoutError as PlaywrightTimeout
from playwright.async_api import async_playwright

OUT = Path(__file__).parent / "output"


async def state(page):
    text = await page.evaluate("() => window.homemaps || null")
    return json.loads(text) if text else {}


async def wait(page, description, condition, seconds=60):
    for _ in range(seconds * 2):
        current = await state(page)
        if condition(current):
            print(f"  ok: {description}")
            return current
        await page.wait_for_timeout(500)
    raise AssertionError(f"{description}: never happened (last state {current})")


async def main(base: str, start: str, destination: str) -> None:
    OUT.mkdir(exist_ok=True)
    async with async_playwright() as p:
        browser = await p.chromium.launch(
            args=["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader"]
        )
        page = await browser.new_page(viewport={"width": 1400, "height": 850}, locale="nl-NL")
        errors = []
        # A Dart error in wasm is only called "Exception" in `str()`; the stack and the
        # console (where Flutter puts the real message) tell what went wrong.
        page.on("pageerror", lambda error: errors.append(f"{error}\n{error.stack or ''}"))
        console = []
        page.on("console", lambda message: console.append(f"[{message.type}] {message.text}"))
        try:
            await page.goto(f"{base}/?simulate={start}&speed=25&to={destination}")
            await wait(page, "location on", lambda s: s.get("location") == "enabled")
            planning = await wait(page, "route computed", lambda s: s.get("routes", 0) > 0)
            print(f"  {planning['routes']} route(s)")
            await page.screenshot(path=OUT / "1-route.png")

            # Accessibility tree on, then the button by name.
            await page.locator("flt-semantics-placeholder").dispatch_event("click")
            await page.get_by_role("button", name="Start").click(timeout=15000)
            first = await wait(page, "navigation running", lambda s: s.get("navigating") and s.get("remainingMeters"))
            print(f"  next: {first['next']!r}, {first['remainingMeters']} m to go")
            later = await wait(
                page,
                "the fake GPS drives along the route",
                lambda s: s.get("remainingMeters") is not None
                and s["remainingMeters"] < first["remainingMeters"] - 100
                and not s.get("offRoute"),
            )
            print(f"  {later['remainingMeters']} m to go")
            await page.screenshot(path=OUT / "2-navigation.png")

            await page.get_by_role("button", name="Stop").click(timeout=15000)
            await wait(page, "stopped", lambda s: not s.get("navigating"))
            if errors:
                raise AssertionError(f"errors in the page: {errors}")
        except (AssertionError, PlaywrightTimeout):
            await page.screenshot(path=OUT / "error.png")
            (OUT / "console.txt").write_text("\n".join(console))
            print("\n".join(line for line in console if line.startswith("[error]"))[-4000:])
            raise
        finally:
            await browser.close()
    print("app in the browser: OK")


if __name__ == "__main__":
    asyncio.run(main(*sys.argv[1:4]))

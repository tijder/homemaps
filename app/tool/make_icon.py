"""Draws the app icon: a map pin with a little house inside, on a blue background with a
dotted route. Everything is code, so colour and shape can be changed without a
drawing program.

    python3 tool/make_icon.py             # writes assets/icon/*.png
    dart run flutter_launcher_icons       # turns them into Android, iOS and web icons

Requires Pillow.
"""

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
SCALE = 4  # drawing larger and scaling down gives smooth edges
BLUE_LIGHT, BLUE_DARK = (30, 118, 210), (13, 71, 161)
WHITE = (255, 255, 255, 255)
OUT = Path(__file__).resolve().parent.parent / "assets" / "icon"


def gradient(size):
    """Diagonal gradient from light (top left) to dark (bottom right)."""
    image = Image.new("RGB", (size, size))
    pixels = image.load()
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * size)
            pixels[x, y] = tuple(
                round(a + (b - a) * t) for a, b in zip(BLUE_LIGHT, BLUE_DARK, strict=True)
            )
    return image


def route(image, size):
    """A dotted S-curve running behind the pin: that's where 'maps' comes from. Drawn on
    its own layer and made translucent in one go, so overlapping dots don't get
    brighter."""
    layer = Image.new("RGBA", image.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    radius = size * 0.02
    for step in range(0, 17):
        t = step / 16
        x = size * (0.11 + 0.78 * t)
        y = size * (0.80 - 0.13 * math.sin(t * math.pi * 2) - 0.10 * t)
        draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=WHITE)
    layer.putalpha(layer.split()[3].point(lambda a: a * 0.6))
    image.alpha_composite(layer)


def pin(draw, size, cx, cy, height):
    """The teardrop shape: a circle with a point below it. (cx, cy) is the point."""
    radius = height * 0.36
    center_y = cy - height + radius
    draw.ellipse((cx - radius, center_y - radius, cx + radius, center_y + radius), fill=WHITE)
    # The tangents from the point to the circle.
    distance = cy - center_y
    angle = math.acos(radius / distance)
    left = (cx - radius * math.sin(angle), center_y + radius * math.cos(angle))
    right = (cx + radius * math.sin(angle), center_y + radius * math.cos(angle))
    draw.polygon([left, right, (cx, cy)], fill=WHITE)
    return center_y, radius


def house(draw, cx, cy, size, colour):
    """A little house: roof, front and a door, centred on (cx, cy)."""
    width, height = size, size * 0.92
    roof = height * 0.48
    top, bottom = cy - height / 2, cy + height / 2
    draw.polygon(
        [(cx, top), (cx + width * 0.60, top + roof), (cx - width * 0.60, top + roof)],
        fill=colour,
    )
    draw.rectangle((cx - width * 0.42, top + roof * 0.86, cx + width * 0.42, bottom), fill=colour)
    door_w, door_h = width * 0.13, height * 0.30
    draw.rectangle((cx - door_w, bottom - door_h, cx + door_w, bottom + 1), fill=WHITE)


def draw_foreground(size, pin_height):
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    cx, tip_y = size / 2, size / 2 + pin_height / 2
    center_y, radius = pin(draw, size, cx, tip_y, pin_height)
    house(draw, cx, center_y, radius * 1.05, BLUE_DARK + (255,))
    return image


def shadow(foreground, size):
    alpha = foreground.split()[3].filter(ImageFilter.GaussianBlur(size * 0.018))
    black = Image.new("RGBA", foreground.size, (0, 0, 0, 0))
    black.putalpha(alpha.point(lambda a: a * 0.35))
    shifted = Image.new("RGBA", foreground.size, (0, 0, 0, 0))
    shifted.paste(black, (0, round(size * 0.015)), black)
    return shifted


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    large = SIZE * SCALE

    # The full icon (web, favicon, older Android): rounded corners.
    background = gradient(large).convert("RGBA")
    route(background, large)
    pin_layer = draw_foreground(large, large * 0.62)
    background.alpha_composite(shadow(pin_layer, large))
    background.alpha_composite(pin_layer)
    # iOS rounds the corners itself and rejects icons with transparency: same image up to the edge.
    background.convert("RGB").resize((SIZE, SIZE), Image.LANCZOS).save(OUT / "icon-ios.png")
    mask = Image.new("L", (large, large), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, large, large), radius=large * 0.22, fill=255)
    background.putalpha(mask)
    background.resize((SIZE, SIZE), Image.LANCZOS).save(OUT / "icon.png")

    # Adaptive icon (Android 8+): the system cuts out a shape itself, so the
    # background runs to the edge and the pin stays within the safe 66%.
    plane = gradient(large).convert("RGBA")
    route(plane, large)
    plane.resize((SIZE, SIZE), Image.LANCZOS).save(OUT / "icon-background.png")
    foreground = draw_foreground(large, large * 0.44)
    combined = Image.new("RGBA", (large, large), (0, 0, 0, 0))
    combined.alpha_composite(shadow(foreground, large))
    combined.alpha_composite(foreground)
    combined.resize((SIZE, SIZE), Image.LANCZOS).save(OUT / "icon-foreground.png")
    for name in ("icon", "icon-ios", "icon-background", "icon-foreground"):
        print(OUT / f"{name}.png")


if __name__ == "__main__":
    main()

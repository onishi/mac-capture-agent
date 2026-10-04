#!/usr/bin/env python3
"""Generates the app icon (spy reticle) into Sources/AmbientApp/Resources/Assets.xcassets.

Requires Pillow: pip install pillow
"""
import json
import os
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICONSET = os.path.join(ROOT, "Sources/AmbientApp/Resources/Assets.xcassets/AppIcon.appiconset")
CYAN = (89, 237, 255)
AMBER = (255, 184, 64)


def render(size: int) -> Image.Image:
    scale = 4  # supersample
    s = size * scale
    image = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    inset = int(s * 0.09)
    radius = int(s * 0.2)
    # dark glass body with a subtle top gradient
    body = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    bdraw = ImageDraw.Draw(body)
    for y in range(inset, s - inset):
        t = (y - inset) / (s - 2 * inset)
        color = (int(10 + 12 * (1 - t)), int(22 + 20 * (1 - t)), int(34 + 26 * (1 - t)), 255)
        bdraw.line([(inset, y), (s - inset, y)], fill=color)
    mask = Image.new("L", (s, s), 0)
    ImageDraw.Draw(mask).rounded_rectangle([inset, inset, s - inset, s - inset], radius=radius, fill=255)
    image.paste(body, (0, 0), mask)
    draw.rounded_rectangle([inset, inset, s - inset, s - inset], radius=radius, outline=(*CYAN, 90), width=max(1, s // 160))

    # scanlines
    for y in range(inset, s - inset, max(2, s // 64)):
        draw.line([(inset + radius // 2, y), (s - inset - radius // 2, y)], fill=(255, 255, 255, 4), width=max(1, s // 512))

    # reticle corner brackets
    glow = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    gdraw = ImageDraw.Draw(glow)
    b0, b1 = int(s * 0.26), int(s * 0.74)
    arm = int(s * 0.12)
    width = max(2, s // 36)
    for (x, y, dx, dy) in [(b0, b0, 1, 1), (b1, b0, -1, 1), (b0, b1, 1, -1), (b1, b1, -1, -1)]:
        gdraw.line([(x, y), (x + dx * arm, y)], fill=(*CYAN, 255), width=width)
        gdraw.line([(x, y), (x, y + dy * arm)], fill=(*CYAN, 255), width=width)
    # center: crosshair ring and amber core
    c = s // 2
    r = int(s * 0.1)
    gdraw.ellipse([c - r, c - r, c + r, c + r], outline=(*CYAN, 230), width=max(2, s // 64))
    tick = int(s * 0.05)
    for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)]:
        gdraw.line([(c + dx * (r + tick // 3), c + dy * (r + tick // 3)), (c + dx * (r + tick), c + dy * (r + tick))],
                   fill=(*CYAN, 230), width=max(2, s // 80))
    core = int(s * 0.03)
    gdraw.ellipse([c - core, c - core, c + core, c + core], fill=(*AMBER, 255))
    blurred = glow.filter(ImageFilter.GaussianBlur(radius=s / 60))
    image = Image.alpha_composite(image, blurred)
    image = Image.alpha_composite(image, glow)
    return image.resize((size, size), Image.LANCZOS)


def main() -> None:
    os.makedirs(ICONSET, exist_ok=True)
    entries = []
    for points in (16, 32, 128, 256, 512):
        for factor in (1, 2):
            pixels = points * factor
            name = f"icon_{points}x{points}{'@2x' if factor == 2 else ''}.png"
            render(pixels).save(os.path.join(ICONSET, name))
            entries.append({"idiom": "mac", "size": f"{points}x{points}", "scale": f"{factor}x", "filename": name})
    with open(os.path.join(ICONSET, "Contents.json"), "w") as f:
        json.dump({"images": entries, "info": {"author": "xcode", "version": 1}}, f, indent=2)
    with open(os.path.join(os.path.dirname(ICONSET), "Contents.json"), "w") as f:
        json.dump({"info": {"author": "xcode", "version": 1}}, f, indent=2)


if __name__ == "__main__":
    main()

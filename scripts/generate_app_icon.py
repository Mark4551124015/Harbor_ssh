#!/usr/bin/env python3
"""Generate the macOS app-icon set from the source artwork.

Source: assets/Harbor Terminal Icon.png (the mark on a rounded tile, exported
without an alpha channel). We rebuild the transparent rounded corners, then
resize the artwork into the classic multi-size macOS app-icon set.

Note on automatic light/dark icons: macOS does not switch app icons from the
classic `AppIcon.appiconset` based on appearance/version. On macOS 26+ that is
done with an Icon Composer `.icon` asset (Xcode > Icon Composer), which is a
separate, manually-authored bundle. This script therefore only produces the
standard tile that the OS always uses.

Run from the repository root:

    python3 scripts/generate_app_icon.py

Requires: pillow, numpy, scipy.
"""

import json
import os

import numpy as np
from PIL import Image
from scipy import ndimage

SRC = "assets/Harbor Terminal Icon.png"
APPICON = "macos/Runner/Assets.xcassets/AppIcon.appiconset"
ICON_SIZES = "assets/brand/swift-app-icons"
SIZES = [16, 32, 64, 128, 256, 512, 1024]
# (slot size, filename, scale)
ENTRIES = [
    ("16x16", "app_icon_16.png", "1x"),
    ("16x16", "app_icon_32.png", "2x"),
    ("32x32", "app_icon_32.png", "1x"),
    ("32x32", "app_icon_64.png", "2x"),
    ("128x128", "app_icon_128.png", "1x"),
    ("128x128", "app_icon_256.png", "2x"),
    ("256x256", "app_icon_256.png", "1x"),
    ("256x256", "app_icon_512.png", "2x"),
    ("512x512", "app_icon_512.png", "1x"),
    ("512x512", "app_icon_1024.png", "2x"),
]


def build_tile():
    arr = np.asarray(Image.open(SRC).convert("RGB")).astype(np.float64)
    h, w, _ = arr.shape
    m = arr.max(axis=2)

    # The export has solid black corners; keep only the black region connected to
    # the canvas border as transparent, so enclosed dark shadows stay opaque.
    exterior = m < 8
    labels, _ = ndimage.label(exterior)
    border = set(labels[0, :]) | set(labels[-1, :]) | set(labels[:, 0]) | set(labels[:, -1])
    border.discard(0)
    ext = np.isin(labels, list(border))

    alpha = np.ones((h, w))
    alpha[ext] = 0.0
    band = (~ext) & ndimage.binary_dilation(ext, iterations=3)
    alpha[band] = np.clip(m[band] / 45.0, 0.0, 1.0)

    rgb = arr.copy()
    semi = (alpha > 0.001) & (alpha < 1.0)
    rgb[semi] = np.clip(arr[semi] / alpha[semi, None], 0, 255)
    return Image.fromarray(np.dstack([rgb, alpha * 255]).astype(np.uint8), "RGBA")


def write_sizes(tile):
    os.makedirs(ICON_SIZES, exist_ok=True)
    os.makedirs(APPICON, exist_ok=True)
    for path in os.listdir(APPICON):
        if path.startswith("app_icon_"):
            os.remove(os.path.join(APPICON, path))
    for size in SIZES:
        resized = tile.resize((size, size), Image.LANCZOS)
        resized.save(os.path.join(ICON_SIZES, f"{size}.png"))
        resized.save(os.path.join(APPICON, f"app_icon_{size}.png"))


def write_contents():
    images = [
        {"size": size, "idiom": "mac", "filename": filename, "scale": scale}
        for size, filename, scale in ENTRIES
    ]
    doc = {"images": images, "info": {"version": 1, "author": "xcode"}}
    with open(os.path.join(APPICON, "Contents.json"), "w") as handle:
        json.dump(doc, handle, indent=2)
        handle.write("\n")


def main():
    tile = build_tile()
    write_sizes(tile)
    write_contents()
    print(f"Wrote {len(SIZES)} icons to {APPICON}")


if __name__ == "__main__":
    main()

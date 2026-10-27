#!/usr/bin/env python3
"""Draws Lowdrift's app icon variants and Now Playing artwork.

Layered airflow waves in sea-glass teal: a light default icon, a midnight dark
icon, a grayscale tinted icon and the lock-screen artwork. Requires Pillow and
NumPy (developer tool only; the app itself has no dependencies).

    python3 scripts/make_icons.py
"""
import os

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "Lowdrift", "Resources", "Assets.xcassets")
SCALE = 2  # draw large, then downsample for smooth edges


def hex_rgb(value):
    value = value.lstrip("#")
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


def vertical_gradient(size, top, bottom):
    t = np.linspace(0, 1, size)[:, None, None]
    top = np.array(hex_rgb(top), dtype=float)[None, None, :]
    bottom = np.array(hex_rgb(bottom), dtype=float)[None, None, :]
    rows = top * (1 - t) + bottom * t
    pixels = np.repeat(rows, size, axis=1)
    return Image.fromarray(pixels.astype(np.uint8), "RGB").convert("RGBA")


# baseline, amplitude, wavelength (fractions of the canvas), phase, width, opacity
LAYERS = [
    (0.355, 0.035, 1.10, 0.6, 0.014, 0.40),
    (0.445, 0.048, 0.90, 2.2, 0.020, 0.62),
    (0.550, 0.058, 1.30, 4.1, 0.032, 1.00),
    (0.655, 0.040, 0.80, 5.3, 0.018, 0.55),
]
MAIN_LAYER = 2


def curve(u, baseline, amplitude, wavelength, phase):
    """Wave height and slope at horizontal positions u (0…1)."""
    t = u / wavelength * 2 * np.pi + phase
    shape = (np.sin(t) + 0.35 * np.sin(0.53 * t + 1.3)) / 1.35
    slope = (np.cos(t) + 0.35 * 0.53 * np.cos(0.53 * t + 1.3)) / 1.35 * 2 * np.pi / wavelength
    return baseline + amplitude * shape, amplitude * slope


def draw_icon(background_top, background_bottom, wave, wash, size=1024, grayscale=False):
    big = size * SCALE
    image = np.asarray(vertical_gradient(big, background_top, background_bottom).convert("RGB"), dtype=float) / 255
    u = (np.arange(big) + 0.5) / big
    v = ((np.arange(big) + 0.5) / big)[:, None]
    wave_rgb = np.array(hex_rgb(wave), dtype=float) / 255
    wash_rgb = np.array(hex_rgb(wash), dtype=float) / 255

    def blend(alpha, rgb):
        nonlocal image
        image = image * (1 - alpha[..., None]) + rgb[None, None, :] * alpha[..., None]

    # Soft wash under the main wave, fading downward.
    height, _ = curve(u, *LAYERS[MAIN_LAYER][:4])
    below = v - height[None, :]
    wash_alpha = np.where(below > 0, 0.16 * np.exp(-below / 0.16) * np.clip(below / 0.01, 0, 1), 0)
    blend(wash_alpha, wash_rgb)

    # Anti-aliased strokes from the distance to each curve.
    for baseline, amplitude, wavelength, phase, width, opacity in LAYERS:
        height, slope = curve(u, baseline, amplitude, wavelength, phase)
        distance = np.abs(v - height[None, :]) / np.sqrt(1 + slope[None, :] ** 2)
        pixel = 1 / big
        coverage = np.clip((width / 2 - distance) / pixel + 0.5, 0, 1)
        blend(coverage * opacity, wave_rgb)

    result = Image.fromarray((np.clip(image, 0, 1) * 255).astype(np.uint8), "RGB")
    result = result.resize((size, size), Image.LANCZOS)
    if grayscale:
        result = result.convert("L").convert("RGB")
    return result


def main():
    icon_dir = os.path.join(ASSETS, "AppIcon.appiconset")
    art_dir = os.path.join(ASSETS, "NowPlayingArtwork.imageset")
    os.makedirs(icon_dir, exist_ok=True)
    os.makedirs(art_dir, exist_ok=True)

    light = draw_icon("#E4F2EF", "#C9E5DF", wave="#226F68", wash="#226F68")
    dark = draw_icon("#16303A", "#0C161E", wave="#9BD7CC", wash="#9BD7CC")
    # Tinted icons are grayscale; the system applies the tint colour.
    tinted = draw_icon("#000000", "#000000", wave="#FFFFFF", wash="#FFFFFF", grayscale=True)

    light.save(os.path.join(icon_dir, "AppIcon.png"))
    dark.save(os.path.join(icon_dir, "AppIcon-Dark.png"))
    tinted.save(os.path.join(icon_dir, "AppIcon-Tinted.png"))
    draw_icon("#16303A", "#0C161E", wave="#9BD7CC", wash="#9BD7CC", size=600).save(
        os.path.join(art_dir, "NowPlayingArtwork.png"))


if __name__ == "__main__":
    main()

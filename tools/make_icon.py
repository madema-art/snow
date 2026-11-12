#!/usr/bin/env python3
"""Packs branding/icon_1024.png into branding/snow.ico (16..256 px) and writes
the smaller PNG previews. Requires Pillow. Run after tools/render_branding.js."""
import os
from PIL import Image

here = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "branding")
src = Image.open(os.path.join(here, "source", "icon_1024.png")).convert("RGBA")
sizes = [16, 24, 32, 48, 64, 128, 256]
src.resize((256, 256), Image.LANCZOS).save(os.path.join(here, "icon_256.png"))
src.resize((64, 64), Image.LANCZOS).save(os.path.join(here, "icon_64.png"))
src.save(os.path.join(here, "snow.ico"), format="ICO", sizes=[(s, s) for s in sizes])
print("snow.ico:", sizes)

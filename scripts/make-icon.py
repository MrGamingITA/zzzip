#!/usr/bin/env python3
"""Icon artwork → AppIcon.appiconset (macOS grid) + DocIcon.icns. Usage: python3 scripts/make-icon.py assets/PandaCuscino.png"""
import sys, json, os, subprocess, tempfile, shutil
from PIL import Image, ImageDraw, ImageChops

src = Image.open(sys.argv[1]).convert("RGB")
root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
out_set = os.path.join(root, "Zzzip/Resources/Assets.xcassets/AppIcon.appiconset")
os.makedirs(out_set, exist_ok=True)
with open(os.path.join(root, "Zzzip/Resources/Assets.xcassets/Contents.json"), "w") as f:
    json.dump({"info": {"author": "xcode", "version": 1}}, f)

# 1. alpha = everything except the dark background connected to the image border
from PIL import ImageFilter
W, H = src.size
dark = src.convert("L").point(lambda v: 255 if v <= 40 else 0)   # 255 = dark
bgmask = dark.copy()
for seed in [(0, 0), (W - 1, 0), (0, H - 1), (W - 1, H - 1), (W // 2, 0), (W // 2, H - 1), (0, H // 2), (W - 1, H // 2)]:
    if bgmask.getpixel(seed) == 255:
        ImageDraw.floodfill(bgmask, seed, 128)
alpha = bgmask.point(lambda v: 0 if v == 128 else 255)
alpha = alpha.filter(ImageFilter.MinFilter(5)).filter(ImageFilter.GaussianBlur(1.5))  # trim dark fringe, soften edge
art = src.convert("RGBA"); art.putalpha(alpha)
box = alpha.point(lambda v: 255 if v > 128 else 0).getbbox()
art = art.crop(box)

# 2. scale to the macOS icon body (824 on a 1024 canvas, square-ish bounding box preserved)
BODY, CANVAS = 824, 1024
scale = BODY / max(art.size)
body = art.resize((round(art.width * scale), round(art.height * scale)), Image.LANCZOS)
mask = body.getchannel("A")
canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
off = ((CANVAS - body.width) // 2, (CANVAS - body.height) // 2)
# soft drop shadow like system icons
shadow = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
shadow_layer = Image.new("RGBA", body.size, (0, 0, 0, 90)); shadow_layer.putalpha(mask.point(lambda v: v * 90 // 255))
shadow.paste(shadow_layer, (off[0], off[1] + 12), shadow_layer)
shadow = shadow.filter(__import__("PIL.ImageFilter", fromlist=["GaussianBlur"]).GaussianBlur(14))
canvas = Image.alpha_composite(canvas, shadow)
canvas.paste(body, off, body)

images = []
for size in [16, 32, 128, 256, 512]:
    for scale in [1, 2]:
        px = size * scale
        name = f"icon_{size}x{size}{'@2x' if scale == 2 else ''}.png"
        canvas.resize((px, px), Image.LANCZOS).save(os.path.join(out_set, name))
        images.append({"idiom": "mac", "size": f"{size}x{size}", "scale": f"{scale}x", "filename": name})
with open(os.path.join(out_set, "Contents.json"), "w") as f:
    json.dump({"images": images, "info": {"author": "xcode", "version": 1}}, f, indent=2)
canvas.save(os.path.join(root, "assets/AppIcon-1024.png"))

# 3. document icon for associated archives (zip, rar, 7z…): the same artwork as the app icon
def doc_icon(px):
    return canvas.resize((px, px), Image.LANCZOS)

tmp = tempfile.mkdtemp()
iconset = os.path.join(tmp, "DocIcon.iconset"); os.makedirs(iconset)
for size in [16, 32, 128, 256, 512]:
    for scale in [1, 2]:
        doc_icon(size * scale).save(os.path.join(iconset, f"icon_{size}x{size}{'@2x' if scale == 2 else ''}.png"))
subprocess.run(["iconutil", "-c", "icns", iconset, "-o", os.path.join(root, "Zzzip/Resources/DocIcon.icns")], check=True)
doc_icon(512).save(os.path.join(root, "assets/DocIcon-512.png"))
shutil.rmtree(tmp)
print("ok", box)

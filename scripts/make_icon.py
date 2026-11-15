"""Generate a simple geometric application icon (development helper, Pillow)."""
import json
from pathlib import Path
from PIL import Image, ImageDraw

root = Path(__file__).resolve().parents[1] / "QuietCamera" / "Assets.xcassets"
folder = root / "AppIcon.appiconset"
folder.mkdir(parents=True, exist_ok=True)
image = Image.new("RGB", (1024, 1024), "#101b18")
draw = ImageDraw.Draw(image)
mint = "#a6f0d1"
draw.rounded_rectangle((176, 300, 848, 758), radius=100, outline=mint, width=35)
draw.rounded_rectangle((325, 235, 551, 340), radius=35, fill=mint)
draw.ellipse((351, 361, 673, 683), outline=mint, width=34)
draw.ellipse((416, 426, 608, 618), fill=mint)
draw.ellipse((734, 369, 769, 404), fill=mint)
image.save(folder / "AppIcon.png")
(folder / "Contents.json").write_text(json.dumps({"images": [{"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}], "info": {"author": "xcode", "version": 1}}, indent=2), encoding="utf-8")
(root / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2), encoding="utf-8")
print("Created 1024px opaque app icon")

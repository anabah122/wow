import os
from pathlib import Path
from PIL import Image
from concurrent.futures import ThreadPoolExecutor

ROOT       = Path(__file__).resolve().parent.parent
SOURCE_DIR = ROOT / "tools" / "Tileset"     # .blp здесь
OUTPUT_DIR = ROOT / "assets" / "Tileset"    # .png сюда, структура идентична

def convert(blp_path: Path):
    try:
        rel      = blp_path.relative_to(SOURCE_DIR)
        png_path = OUTPUT_DIR / rel.with_suffix('.png')
        png_path.parent.mkdir(parents=True, exist_ok=True)
        with Image.open(blp_path) as img:
            img = img.convert('RGBA')
            if img.size != (256, 256):
                img = img.resize((256, 256), Image.LANCZOS)
            img.save(png_path, 'PNG')
    except Exception as e:
        print(f"err {blp_path}: {e}")

def main():
    files = list(SOURCE_DIR.rglob("*.blp"))
    print(f"found: {len(files)}")
    if not files:
        return
    with ThreadPoolExecutor() as ex:
        ex.map(convert, files)
    print(f"done -> {OUTPUT_DIR}")

if __name__ == "__main__":
    main()

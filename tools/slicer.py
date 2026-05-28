"""
Нарезка текстуры на тайлы (TILE+1)x(TILE+1) с overlap=1 пиксель.
Формат файла не меняется — что на входе, то и на выходе.
Запуск: python tools/slicer.py
"""

import os
from PIL import Image

INPUT  = 'tools/render (2).png'
OUTPUT = 'assets/maps'
TILE   = 256


def slice_image(src_path: str, out_dir: str, tile: int) -> None:
    img = Image.open(src_path)
    w, h = img.size
    os.makedirs(out_dir, exist_ok=True)
    size = tile + 1
    cols = (w + tile - 1) // tile
    rows = (h + tile - 1) // tile

    for row in range(rows):
        for col in range(cols):
            x, y = col * tile, row * tile
            right  = min(x + size, w)
            bottom = min(y + size, h)
            crop = img.crop((x, y, right, bottom))
            if crop.size != (size, size):
                pad = Image.new(img.mode, (size, size))
                pad.paste(crop, (0, 0))
                crop = pad
            crop.save(os.path.join(out_dir, f'{col}_{row}.png'))

    print(f'done: {cols*rows} tiles, grid {cols}x{rows}, tile {size}x{size}')


if __name__ == '__main__':
    slice_image(INPUT, OUTPUT, TILE)

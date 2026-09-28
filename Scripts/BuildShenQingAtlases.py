"""Register and slice imagegen's approved coarse-pixel Shen Qing sheets.

Requires Pillow and NumPy. No artwork is drawn here: all poses come from the
source PNGs. A single nearest-neighbor scale per sheet and a crown anchor keep
frame registration independent of moving hands, bells and sleep glyphs.
"""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import statistics

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ATLAS = ROOT / 'Assets/Source/AnimationAtlases'
SPRITES = ROOT / 'Assets/Sprites'
ACTIONS = ('idle', 'blink', 'wave', 'heart', 'working', 'success', 'error',
           'sleeping', 'reminder', 'hit', 'question')
CELL = 362
ANCHOR = (170, 86)
OUTLINE_MASKS = ATLAS / 'shenqing-v3-outline-masks'


def erase_outer_outline(action, frames):
    """Apply reviewed erasure masks without repainting or moving any pixels."""
    manifest = json.loads((OUTLINE_MASKS / 'manifest.json').read_text())
    fingerprint = hashlib.sha256(b''.join(frame.tobytes() for frame in frames)).hexdigest()
    if fingerprint != manifest[action]:
        raise ValueError(f'{action}: source artwork/registration changed; review the outline mask first')
    mask = Image.open(OUTLINE_MASKS / f'{action}.png').convert('L')
    if mask.size != (CELL * 4, CELL * 2):
        raise ValueError(f'{action}: outline mask must match the normalized atlas')
    cleaned = []
    for index, frame in enumerate(frames):
        x, y = (index % 4) * CELL, (index // 4) * CELL
        erase = np.asarray(mask.crop((x, y, x + CELL, y + CELL))) > 0
        pixels = np.array(frame)
        pixels[erase] = 0
        cleaned.append(Image.fromarray(pixels))
    return cleaned


def crown(image):
    rgba = np.asarray(image).astype(np.int16)
    r, g, b, a = (rgba[:, :, i] for i in range(4))
    mask = (b > 140) & (g > 70) & (b > r * 1.5) & (a > 128)
    # Exclude blue laptop screens or sleep glyphs outside the crown region.
    mask[round(image.height * .35):, :] = False
    mask[:, :round(image.width * .30)] = False
    mask[:, round(image.width * .70):] = False
    y, x = np.where(mask)
    if len(x) < 12:
        raise ValueError('Missing blue crown registration marker')
    return ((int(x.min()) + int(x.max())) / 2,
            (int(y.min()) + int(y.max())) / 2,
            int(x.max()) - int(x.min()) + 1)


def registered_frames(action):
    source = Image.open(ATLAS / f'shenqing-{action}-v3-source.png').convert('RGBA')
    if not 1.95 < source.width / source.height < 2.05:
        raise ValueError(f'{action}: expected a 4 x 2 source sheet')
    cells = [source.crop((round(col * source.width / 4), round(row * source.height / 2),
                          round((col + 1) * source.width / 4), round((row + 1) * source.height / 2)))
             for row in range(2) for col in range(4)]
    markers = [crown(cell) for cell in cells]
    scale = 56 / statistics.median(marker[2] for marker in markers)
    frames = []
    for cell, (cx, cy, _) in zip(cells, markers):
        pixels = np.array(cell)
        pixels[:, :, 3] = np.where(pixels[:, :, 3] >= 128, 255, 0)
        pixels[pixels[:, :, 3] == 0] = 0
        cell = Image.fromarray(pixels).resize(
            (round(cell.width * scale), round(cell.height * scale)), Image.Resampling.NEAREST)
        x, y = round(ANCHOR[0] - cx * scale), round(ANCHOR[1] - cy * scale)
        bounds = cell.getbbox()
        if not bounds or min(bounds[0] + x, bounds[1] + y) < 0 or max(bounds[2] + x, bounds[3] + y) > CELL:
            raise ValueError(f'{action}: sprite exceeds the fixed canvas after registration')
        frame = Image.new('RGBA', (CELL, CELL))
        frame.paste(cell, (x, y))
        frames.append(frame)
    # The source choreography is a closed cycle. Reuse its exact initial frame
    # at the seam, avoiding generation noise when the animation loops/restores.
    frames[-1] = frames[0].copy()
    return erase_outer_outline(action, frames), scale


def archive_previous():
    destination = ROOT / 'Assets/Archive/Sprites/shenqing-before-v3'
    if any(destination.glob('*.png')):
        return  # The previous artwork is already preserved; never archive v3 as v1.
    destination.mkdir(parents=True, exist_ok=True)
    for path in SPRITES.glob('shenqing-*.png'):
        saved = destination / path.name
        if not saved.exists():
            shutil.copy2(path, saved)
    destination = ROOT / 'Assets/Archive/AnimationAtlases/shenqing-v1'
    destination.mkdir(parents=True, exist_ok=True)
    for path in ATLAS.glob('shenqing-*-v1*.png'):
        if not (destination / path.name).exists():
            shutil.move(str(path), str(destination / path.name))


def build(selected):
    # Validate every selected sheet before touching the runtime assets.
    prepared = {action: registered_frames(action) for action in selected}
    archive_previous()
    report = {}
    for action, (frames, scale) in prepared.items():
        atlas = Image.new('RGBA', (CELL * 4, CELL * 2))
        for index, frame in enumerate(frames):
            atlas.paste(frame, ((index % 4) * CELL, (index // 4) * CELL))
            frame.save(SPRITES / f'shenqing-{action}-{index + 1:02}.png')
        atlas.save(ATLAS / f'shenqing-{action}-v3.png')
        report[action] = {'frames': len(frames), 'scale': scale, 'canvas': [CELL, CELL],
                          'crown_anchor': list(ANCHOR), 'bounds': [frame.getbbox() for frame in frames]}
    if 'working' in selected:
        for index in range(9, 17):
            stale = SPRITES / f'shenqing-working-{index:02}.png'
            if stale.exists():
                stale.unlink()  # Preserved by archive_previous above.
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('actions', nargs='*')
    args = parser.parse_args()
    if set(args.actions) - set(ACTIONS):
        parser.error('Unknown animation action')
    build(args.actions or ACTIONS)

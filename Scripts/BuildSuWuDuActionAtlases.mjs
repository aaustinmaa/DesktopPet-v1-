// Normalize only SuWuDu's imagegen wave/reminder sources. Requires Node + sharp.
// SHARP_MODULE may point to an existing sharp installation without installing packages.
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import fs from 'node:fs/promises';

const require = createRequire(import.meta.url);
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const atlasDir = path.join(root, 'Assets/Source/AnimationAtlases');
const spriteDir = path.join(root, 'Assets/Sprites');
const cellSize = 362;
const definitions = [
  {
    name: 'wave-v3', rows: 4, interval: 100,
    // Reuse the reviewed rise in reverse to settle; repeat the same wave poses.
    // This also avoids the generated last row, whose feet touch the image edge.
    sequence: [0, 1, 2, 3, 4, 5, 6, 7, 4, 5, 6, 7, 3, 2, 1, 0],
  },
  {
    name: 'reminder-v3', rows: 4, interval: 90,
    // Reviewed transparent gutters in the wave-matched source: the first bell
    // extends beyond the nominal quarter-width boundary in rows 2 and 4.
    columnEdges: [0, 325, 627, 940, 1254],
    // Finish on the exact opening pose.
    sequence: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 0],
  },
];
const animationName = process.argv[2];
if (process.argv.length > 3 || (animationName && !definitions.some(definition => definition.name === animationName))) {
  throw new Error(`Usage: node Scripts/BuildSuWuDuActionAtlases.mjs [${definitions.map(definition => definition.name).join('|')}]`);
}
const selectedDefinitions = animationName
  ? definitions.filter(definition => definition.name === animationName)
  : definitions;
const sharp = require(process.env.SHARP_MODULE || 'sharp');

function contentBands(data, width, height) {
  const bands = [];
  let start = null;
  for (let y = 0; y <= height; y++) {
    let count = 0;
    for (let x = 0; y < height && x < width; x++) {
      if (data[(y * width + x) * 4 + 3] >= 224) count++;
    }
    if (count >= 20 && start === null) start = y;
    if (count < 20 && start !== null) {
      bands.push([start, y - 1]);
      start = null;
    }
  }
  return bands;
}

function bounds(data, width, left, right, top, bottom, predicate) {
  let x0 = right, y0 = bottom, x1 = -1, y1 = -1;
  for (let y = top; y <= bottom; y++) {
    for (let x = left; x < right; x++) {
      const p = (y * width + x) * 4;
      if (!predicate(data[p], data[p + 1], data[p + 2], data[p + 3], x, y)) continue;
      x0 = Math.min(x0, x); y0 = Math.min(y0, y);
      x1 = Math.max(x1, x); y1 = Math.max(y1, y);
    }
  }
  if (x1 < x0) throw new Error('Missing character or crown in source cell');
  return { x0, y0, x1, y1 };
}

function copyPixels(source, width, height, destination, destinationWidth, x, y) {
  for (let row = 0; row < height; row++) {
    source.copy(destination, ((y + row) * destinationWidth + x) * 4,
      row * width * 4, (row + 1) * width * 4);
  }
}

const manifestPath = path.join(atlasDir, 'suwudu-actions-v3-registration.json');
// A targeted rebuild retains registration for every unselected animation.
const manifest = animationName
  ? JSON.parse(await fs.readFile(manifestPath, 'utf8'))
  : { cellSize, columns: 4, rows: 4, animations: [] };
await fs.mkdir(spriteDir, { recursive: true });
for (const definition of selectedDefinitions) {
  const source = path.join(atlasDir, `${definition.name}-source.png`);
  const { data, info } = await sharp(source).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  if (definition.columnEdges && definition.columnEdges[4] !== info.width) {
    throw new Error(`${source}: review column gutters for the changed source dimensions`);
  }
  const bands = contentBands(data, info.width, info.height);
  if (bands.length !== definition.rows) throw new Error(`${source}: unexpected row layout`);
  // One scale for the whole sheet, independent of the moving hand and bell.
  const heights = bands.map(([top, bottom]) => bottom - top + 1).sort((a, b) => a - b);
  let scale = 304 / heights[Math.floor(heights.length / 2)];
  const poses = new Map();
  const registration = [];
  const measurements = [];
  for (const index of new Set(definition.sequence)) {
    const column = index % 4;
    const left = definition.columnEdges?.[column] ?? Math.round(column * info.width / 4);
    const right = definition.columnEdges?.[column + 1] ?? Math.round((column + 1) * info.width / 4);
    const [bandTop, bandBottom] = bands[Math.floor(index / 4)];
    const top = Math.max(0, bandTop - 3);
    const bottom = Math.min(info.height - 1, bandBottom + 3);
    const body = bounds(data, info.width, left, right, top, bottom, (r, g, b, a) => a >= 192);
    const crown = bounds(data, info.width, left, right, bandTop,
      Math.floor(bandTop + (bandBottom - bandTop + 1) * 0.24),
      (r, g, b, a, x) => a >= 192 && g > 120 && b < 100 && g > r * 0.7
        && x > left + (right - left) * 0.25 && x < left + (right - left) * 0.8);
    const cropLeft = Math.max(left, body.x0 - 3);
    const cropTop = Math.max(top, body.y0 - 3);
    const cropWidth = Math.min(right - 1, body.x1 + 3) - cropLeft + 1;
    const cropHeight = Math.min(bottom, body.y1 + 3) - cropTop + 1;
    const crownX = (crown.x0 + crown.x1) / 2;
    // Reserve an eight-pixel margin for the full bell swing. Apply the most
    // restrictive fit to the entire animation, never individual frames.
    scale = Math.min(scale, 172 / (crownX - cropLeft),
      174 / (cropLeft + cropWidth - crownX),
      36 / (crown.y0 - cropTop), 310 / (cropTop + cropHeight - crown.y0));
    measurements.push({ index, crown, cropLeft, cropTop, cropWidth, cropHeight });
  }
  for (const { index, crown, cropLeft, cropTop, cropWidth, cropHeight } of measurements) {
    const width = Math.round(cropWidth * scale), height = Math.round(cropHeight * scale);
    const x = Math.round(180 - ((crown.x0 + crown.x1) / 2 - cropLeft) * width / cropWidth);
    const y = Math.round(44 - (crown.y0 - cropTop) * height / cropHeight);
    if (x < 0 || y < 0 || x + width > cellSize || y + height > cellSize) {
      throw new Error(`${definition.name} pose ${index + 1}: artwork exceeds fixed cell (${x}, ${y}, ${width}, ${height})`);
    }
    // Nearest-neighbor resampling and translation only: retain generated RGBA.
    const crop = await sharp(source)
      .extract({ left: cropLeft, top: cropTop, width: cropWidth, height: cropHeight })
      .resize(width, height, { kernel: 'nearest', fit: 'fill' }).ensureAlpha().raw().toBuffer();
    const frame = Buffer.alloc(cellSize * cellSize * 4);
    copyPixels(crop, width, height, frame, cellSize, x, y);
    poses.set(index, frame);
    registration.push({ sourcePose: index + 1, crop: [cropLeft, cropTop, cropWidth, cropHeight],
      destination: [x, y, width, height] });
  }
  const atlas = Buffer.alloc(cellSize * 4 * cellSize * 4 * 4);
  for (const [index, pose] of definition.sequence.entries()) {
    const frame = poses.get(pose);
    await sharp(frame, { raw: { width: cellSize, height: cellSize, channels: 4 } }).png()
      .toFile(path.join(spriteDir, `${definition.name}-${String(index + 1).padStart(2, '0')}.png`));
    copyPixels(frame, cellSize, cellSize, atlas, cellSize * 4,
      (index % 4) * cellSize, Math.floor(index / 4) * cellSize);
  }
  await sharp(atlas, { raw: { width: cellSize * 4, height: cellSize * 4, channels: 4 } })
    .png().toFile(path.join(atlasDir, `${definition.name}.png`));
  const animation = { name: definition.name, intervalMs: definition.interval,
    sourceGrid: [4, definition.rows], sourcePoseSequence: definition.sequence.map(i => i + 1),
    scale, registration };
  const existingIndex = manifest.animations.findIndex(entry => entry.name === definition.name);
  if (existingIndex >= 0) manifest.animations[existingIndex] = animation;
  else manifest.animations.push(animation);
  console.log(`${definition.name}: 16 RGBA frames, 362x362; atlas 1448x1448`);
}
await fs.writeFile(manifestPath, JSON.stringify(manifest, null, 2) + '\n');

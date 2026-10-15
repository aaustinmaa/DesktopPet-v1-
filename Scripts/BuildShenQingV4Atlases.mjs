// Mechanically register imagegen's Shen Qing v4 artwork; never repaint pixels.
// Usage: SHARP_MODULE=/path/to/sharp node Scripts/BuildShenQingV4Atlases.mjs [--check] [--timing-only] [idle ...]
// With no action names all eleven sheets and the layered sleep pose are preflighted.
// --timing-only reads existing runtime PNGs and writes only GIFs, preview and timing metadata.
// --draft-hit exports the guard proposal only in Source; it never updates runtime sprites.
import { createRequire } from 'node:module';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import fs from 'node:fs/promises';

const require = createRequire(import.meta.url);
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const atlasDir = path.join(root, 'Assets/Source/AnimationAtlases/shenqing-v4');
const spriteDir = path.join(root, 'Assets/Sprites');
const archiveDir = path.join(root, 'Assets/Archive/Sprites/shenqing-before-v4');
const manifestPath = path.join(atlasDir, 'registration.json');
const cellSize = 362;
const margin = 8;
const targetHeight = 304;
const targetAnchor = { x: 170, y: 337 };
const definitions = [
  { name: 'idle', label: '待机', interval: 170,
    sourceSequence: [1, 2, 12, 11, 10, 9, 7, 7, 7, 9, 10, 11, 12, 2, 1, 1] },
  { name: 'blink', label: '眨眼', interval: 80 },
  { name: 'happy', label: '开心', interval: 140 },
  { name: 'wave', label: '挥手', interval: 120 },
  { name: 'heart', label: '举心', interval: 140 },
  { name: 'working', label: '工作', interval: 120,
    sourceSequence: [1, 2, 3, 5, 7, 6, 8, 5, 3, 9, 10, 11, 12, 3, 2, 1] },
  { name: 'success', label: '成功', interval: 120 },
  { name: 'error', label: '出错', interval: 140 },
  { name: 'sleeping', label: '睡眠', interval: 10000, sequence: [1] },
  { name: 'reminder', label: '摇铃提醒', interval: 160 },
  { name: 'hit', label: '点击反应', interval: 60,
    sequence: [1, 2, 3, 4, 5, 6, 7, 6, 5, 4, 3, 2, 16],
    durations: [60, 60, 60, 60, 90, 150, 80, 80, 80, 60, 60, 60, 80] },
  { name: 'question', label: '疑问', interval: 160 },
];
const args = process.argv.slice(2);
const checkOnly = args.includes('--check');
const timingOnly = args.includes('--timing-only');
const draftHit = args.includes('--draft-hit');
const names = args.filter(arg => !['--check', '--timing-only', '--draft-hit'].includes(arg));
if (draftHit && (timingOnly || names.length)) throw new Error('--draft-hit cannot be combined with action names or --timing-only');
if (names.some(name => !definitions.some(definition => definition.name === name))) {
  throw new Error(`Usage: node Scripts/BuildShenQingV4Atlases.mjs [--check] [--timing-only] [${definitions.map(d => d.name).join(' ')}]`);
}
const draftDefinition = { name: 'hit-guard-candidate', label: '受击新稿（未启用）', interval: 70,
  durations: [50, 60, 60, 80, 80, 80, 80, 80, 60, 70, 70, 60, 60, 60, 60, 60] };
const selected = draftHit ? [draftDefinition] : names.length ? definitions.filter(d => names.includes(d.name)) : definitions;
const sharp = require(process.env.SHARP_MODULE || 'sharp');

function timingFor(definition) {
  const playbackFrameSequence = definition.sequence ?? Array.from({ length: 16 }, (_, index) => index + 1);
  const frameDurationsMs = definition.durations ?? playbackFrameSequence.map(() => definition.interval);
  if (frameDurationsMs.length !== playbackFrameSequence.length || frameDurationsMs.some(duration => duration <= 0)) {
    throw new Error(`${definition.name}: each playback frame must have a positive duration`);
  }
  return { intervalMs: definition.interval, playbackFrameSequence, frameDurationsMs,
    totalDurationMs: frameDurationsMs.reduce((sum, duration) => sum + duration, 0) };
}

async function encodePreviewGif(definition, runtimeFrames) {
  const timing = timingFor(definition);
  const gifFrameSequence = [...timing.playbackFrameSequence];
  const gifFrameDurationsMs = [...timing.frameDurationsMs];
  // Frame 16 is the exact opening pose. Combine its loop-seam hold with frame 1
  // rather than dropping that time or asking the GIF encoder to guess the seam.
  if (!runtimeFrames[gifFrameSequence[0] - 1].equals(runtimeFrames[gifFrameSequence.at(-1) - 1])) {
    throw new Error(`${definition.name}: closing runtime frame must equal the opening frame`);
  }
  while (gifFrameSequence.length > 1 && runtimeFrames[gifFrameSequence[0] - 1].equals(runtimeFrames[gifFrameSequence.at(-1) - 1])) {
    gifFrameSequence.pop();
    gifFrameDurationsMs[0] += gifFrameDurationsMs.pop();
  }
  // Explicitly merge identical poses while preserving their hold time.
  for (let index = gifFrameSequence.length - 1; index > 0; index--) {
    if (!runtimeFrames[gifFrameSequence[index] - 1].equals(runtimeFrames[gifFrameSequence[index - 1] - 1])) continue;
    gifFrameDurationsMs[index - 1] += gifFrameDurationsMs[index];
    gifFrameSequence.splice(index, 1);
    gifFrameDurationsMs.splice(index, 1);
  }
  const gif = await sharp(Buffer.concat(gifFrameSequence.map(frame => runtimeFrames[frame - 1])), {
    raw: { width: cellSize, height: cellSize * gifFrameSequence.length, channels: 4, pageHeight: cellSize },
  }).gif({ delay: gifFrameDurationsMs, loop: 0, dither: 0 }).toBuffer();
  const encoded = await sharp(gif, { animated: true }).metadata();
  const encodedDelays = encoded.delay ?? [];
  if (encodedDelays.length !== gifFrameDurationsMs.length
    || encodedDelays.some((duration, index) => duration !== gifFrameDurationsMs[index])) {
    throw new Error(`${definition.name}: encoded GIF frame delays differ from the requested timing`);
  }
  return { gif, timing: { ...timing, gifFrameSequence, gifFrameDurationsMs } };
}

async function preflightTiming(definition, existingManifest) {
  if (!existingManifest) throw new Error(`${definition.name}: --timing-only needs an existing registration entry`);
  if (definition.name === 'sleeping') {
    const base = await sharp(path.join(spriteDir, 'shenqing-sleeping-base.png')).ensureAlpha().raw().toBuffer();
    const { gif, timing } = await encodeSleepingGif(definition, base);
    return { definition, gif, manifest: { ...existingManifest, ...timing } };
  }
  const frames = await Promise.all(Array.from({ length: 16 }, async (_, index) => {
    const filename = path.join(spriteDir, `shenqing-${definition.name}-${String(index + 1).padStart(2, '0')}.png`);
    const { data, info } = await sharp(await fs.readFile(filename)).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
    if (info.width !== cellSize || info.height !== cellSize || info.channels !== 4) {
      throw new Error(`${filename}: expected an existing 362x362 RGBA runtime frame`);
    }
    return data;
  }));
  const { gif, timing } = await encodePreviewGif(definition, frames);
  return { definition, gif, manifest: { ...existingManifest, ...timing } };
}

function median(values) {
  const sorted = [...values].sort((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
}

function pixelBounds(data, width, height, predicate) {
  let x0 = width, y0 = height, x1 = -1, y1 = -1;
  let count = 0;
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const p = (y * width + x) * 4;
      if (!predicate(data[p], data[p + 1], data[p + 2], data[p + 3], x, y)) continue;
      x0 = Math.min(x0, x); y0 = Math.min(y0, y);
      x1 = Math.max(x1, x); y1 = Math.max(y1, y); count++;
    }
  }
  return count ? { x0, y0, x1, y1, count } : null;
}

function findGutter(data, width, height, axis, nominal, crossStart, crossEnd, description) {
  const extent = axis === 'row' ? height : width;
  let best = null;
  for (let edge = Math.max(1, nominal - 24); edge <= Math.min(extent - 1, nominal + 24); edge++) {
    let maximumAlpha = 0, residue = 0;
    for (const line of [edge - 1, edge]) {
      for (let cross = crossStart; cross < crossEnd; cross++) {
        const x = axis === 'row' ? cross : line, y = axis === 'row' ? line : cross;
        const alpha = data[(y * width + x) * 4 + 3];
        maximumAlpha = Math.max(maximumAlpha, alpha);
        residue += alpha;
      }
    }
    // Alpha=1 is invisible generator residue. It remains in the extracted RGBA;
    // this tolerance only chooses a partition, and never erases source pixels.
    if (maximumAlpha > 1) continue;
    const distance = Math.abs(edge - nominal);
    if (!best || residue < best.residue || (residue === best.residue && distance < best.distance)) {
      best = { edge, residue, distance };
    }
  }
  if (!best) throw new Error(`${description}: no transparent ${axis} gutter within 24px of ${nominal}`);
  return best.edge;
}

function mainComponent(data, width, height) {
  const labels = new Int32Array(width * height);
  const queue = new Int32Array(width * height);
  let nextLabel = 0, largest = null;
  for (let start = 0; start < labels.length; start++) {
    if (labels[start] || data[start * 4 + 3] < 128) continue;
    const id = ++nextLabel;
    let head = 0, tail = 1, x0 = width, y0 = height, x1 = -1, y1 = -1;
    labels[start] = id;
    queue[0] = start;
    while (head < tail) {
      const index = queue[head++];
      const x = index % width, y = Math.floor(index / width);
      x0 = Math.min(x0, x); y0 = Math.min(y0, y);
      x1 = Math.max(x1, x); y1 = Math.max(y1, y);
      const neighbours = [x > 0 ? index - 1 : -1, x + 1 < width ? index + 1 : -1,
        y > 0 ? index - width : -1, y + 1 < height ? index + width : -1];
      for (const next of neighbours) {
        if (next < 0 || labels[next] || data[next * 4 + 3] < 128) continue;
        labels[next] = id;
        queue[tail++] = next;
      }
    }
    if (!largest || tail > largest.count) largest = { id, count: tail, x0, y0, x1, y1 };
  }
  return { labels, body: largest };
}

function measure(data, width, height, description, sourceOuterEdges, crownSearchHeight = 0.36) {
  // Source bounds are recorded separately from the reviewed visible-art crop.
  const content = pixelBounds(data, width, height, (r, g, b, a) => a > 0);
  if (!content) throw new Error(`${description}: empty source cell`);
  const visible = pixelBounds(data, width, height, (r, g, b, a) => a >= 16);
  const touches = visible ? { left: visible.x0 === 0, top: visible.y0 === 0,
    right: visible.x1 === width - 1, bottom: visible.y1 === height - 1 } : {};
  if (Object.keys(touches).some(edge => touches[edge] && !sourceOuterEdges[edge])) {
    throw new Error(`${description}: artwork reaches a 4x4 cell boundary; review the source rather than clipping it`);
  }
  // Existing source-edge pixels are retained in full, with the contact recorded.
  const sourceOuterEdgeTouches = Object.keys(touches).filter(edge => touches[edge] && sourceOuterEdges[edge]);
  const { labels, body } = mainComponent(data, width, height);
  if (!body || body.y1 - body.y0 < height * 0.45) {
    throw new Error(`${description}: cannot identify a connected character silhouette`);
  }
  // Sleep Zs and question glyphs are on the left, outside this crown-only region.
  const crown = pixelBounds(data, width, height, (r, g, b, a, x, y) =>
    a >= 128 && x >= width * 0.30 && x <= width * 0.70 && y < height * crownSearchHeight
    && b > 100 && g > 60 && b > r * 1.3 && b - r > 35);
  if (!crown || crown.count < 8 || crown.x1 - crown.x0 > width * 0.35) {
    throw new Error(`${description}: missing or ambiguous blue crown`);
  }
  const crownX = (crown.x0 + crown.x1) / 2;
  const bodyWidth = body.x1 - body.x0 + 1;
  const minimumRun = Math.max(8, Math.round(bodyWidth * 0.35));
  let hemY = null;
  for (let y = body.y1; y >= body.y0 + (body.y1 - body.y0) * 0.65 && hemY === null; y--) {
    let runStart = null;
    for (let x = body.x0; x <= body.x1 + 1; x++) {
      const present = x <= body.x1 && labels[y * width + x] === body.id;
      if (present && runStart === null) runStart = x;
      if (!present && runStart !== null) {
        if (x - runStart >= minimumRun && runStart <= crownX && x > crownX) hemY = y;
        runStart = null;
      }
    }
  }
  if (hemY === null) throw new Error(`${description}: cannot find a continuous lower hem`);
  // Median lower-hair centers ignore hands, red hearts, gold bells and blue glyphs.
  const centers = [];
  const hemTop = Math.max(body.y0, hemY - Math.round((hemY - body.y0) * 0.12));
  for (let y = hemTop; y <= hemY; y++) {
    let first = width, last = -1, count = 0;
    for (let x = body.x0; x <= body.x1; x++) {
      const p = (y * width + x) * 4;
      const r = data[p], g = data[p + 1], b = data[p + 2];
      if (labels[y * width + x] !== body.id || Math.max(r, g, b) > 170
        || Math.max(r, g, b) - Math.min(r, g, b) > 35) continue;
      first = Math.min(first, x); last = x; count++;
    }
    if (count >= 8 && last - first >= minimumRun) centers.push((first + last) / 2);
  }
  if (!centers.length) throw new Error(`${description}: missing dark lower-hair registration pixels`);
  const anchor = { x: median(centers), y: hemY };
  // Leave three pixels around visible artwork. This removes only peripheral
  // almost-transparent generator residue; RGBA inside the crop is untouched.
  const crop = { left: Math.max(0, visible.x0 - 3), top: Math.max(0, visible.y0 - 3) };
  crop.width = Math.min(width, visible.x1 + 4) - crop.left;
  crop.height = Math.min(height, visible.y1 + 4) - crop.top;
  return { anchor, crown, body: { x0: body.x0, y0: body.y0, x1: body.x1, y1: body.y1 },
    content, visible, crop, sourceOuterEdgeTouches, hemRows: [hemTop, hemY], crownToHemHeight: hemY - crown.y0 + 1 };
}

function placement(frame, scale) {
  const width = Math.max(1, Math.round(frame.crop.width * scale));
  const height = Math.max(1, Math.round(frame.crop.height * scale));
  return { width, height,
    left: Math.round(targetAnchor.x - (frame.anchor.x - frame.crop.left) * width / frame.crop.width),
    top: Math.round(targetAnchor.y - (frame.anchor.y - frame.crop.top) * height / frame.crop.height) };
}

function fits(place) {
  return place.left >= margin && place.top >= margin
    && place.left + place.width <= cellSize - margin && place.top + place.height <= cellSize - margin;
}

function copyPixels(source, width, height, destination, destinationWidth, left, top) {
  for (let y = 0; y < height; y++) {
    source.copy(destination, ((top + y) * destinationWidth + left) * 4,
      y * width * 4, (y + 1) * width * 4);
  }
}

// Exact SuWuDu Z choreography, mirrored horizontally for Shen Qing's left-facing pose.
// Glyphs remain readable; only their positions and horizontal travel are mirrored.
// The approved Shen Qing layout moves the mirrored origin 20px left and 30px down.
const sleepZSpecs = [
  { name: 'small', x: 76, y: 102, w: 14, h: 17, appear: .36, fully: .424, arrive: .72, fade: .72, gone: .8, startScale: 1, endScale: 2.29, startX: 0, startY: 0, endX: 51, endY: -56.5 },
  { name: 'medium', x: 48, y: 79, w: 26, h: 31, appear: .18, fully: .244, arrive: .54, fade: .54, gone: .576, startScale: .54, endScale: 1.23, startX: -22, startY: 16, endX: 29, endY: -40.5 },
  { name: 'large', x: 16, y: 34, w: 32, h: 40, appear: 0, fully: .064, arrive: .36, fade: .36, gone: .396, startScale: .43, endScale: 1, startX: -51, startY: 56.5, endX: 0, endY: 0 },
];

async function encodeSleepingGif(definition, base) {
  const glyphs = await Promise.all(sleepZSpecs.map(z => fs.readFile(path.join(spriteDir, `sleeping-z-${z.name}.png`))));
  const frames = [];
  for (let frame = 0; frame < 100; frame++) {
    const t = frame / 100;
    const overlays = [];
    for (const [index, z] of sleepZSpecs.entries()) {
      const opacity = t < z.appear || t >= z.gone ? 0
        : t < z.fully ? (t - z.appear) / (z.fully - z.appear)
        : t <= z.fade ? 1 : (z.gone - t) / (z.gone - z.fade);
      if (opacity <= 0) continue;
      const progress = Math.max(0, Math.min(1, (t - z.appear) / (z.arrive - z.appear)));
      const scale = z.startScale + (z.endScale - z.startScale) * progress;
      const width = Math.round(z.w * scale), height = Math.round(z.h * scale);
      const left = Math.round(z.x - z.startX - (z.endX - z.startX) * progress + (z.w - width) / 2);
      const top = Math.round(z.y + z.startY + (z.endY - z.startY) * progress + (z.h - height) / 2);
      const pixels = await sharp(glyphs[index]).resize(width, height, { kernel: 'nearest', fit: 'fill' }).ensureAlpha().raw().toBuffer();
      for (let p = 3; p < pixels.length; p += 4) pixels[p] = Math.round(pixels[p] * opacity);
      overlays.push({ input: pixels, raw: { width, height, channels: 4 }, left, top });
    }
    frames.push(await sharp(base, { raw: { width: cellSize, height: cellSize, channels: 4 } }).composite(overlays).raw().toBuffer());
  }
  const gif = await sharp(Buffer.concat(frames), {
    raw: { width: cellSize, height: cellSize * frames.length, channels: 4, pageHeight: cellSize },
  }).gif({ delay: frames.map(() => 100), loop: 0, dither: 0 }).toBuffer();
  const encoded = await sharp(gif, { animated: true }).metadata();
  if (encoded.delay.reduce((sum, value) => sum + value, 0) !== 10000) throw new Error('sleeping: GIF must preserve the full 10-second Z cycle');
  return { gif, timing: { ...timingFor(definition), layeredZzz: sleepZSpecs, gifFrameDurationsMs: encoded.delay } };
}

async function preflightSleeping(definition) {
  const sourcePath = path.join(atlasDir, 'sleeping-base-source.png');
  const source = await fs.readFile(sourcePath);
  const { data, info } = await sharp(source).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  const visible = pixelBounds(data, info.width, info.height, (r, g, b, a) => a >= 16);
  if (!visible) throw new Error('sleeping: empty source');
  const su = await sharp(path.join(spriteDir, 'sleeping-base.png')).ensureAlpha().raw().toBuffer();
  const { body } = mainComponent(su, cellSize, cellSize);
  if (!body) throw new Error('sleeping: missing SuWuDu body reference');
  const target = { left: cellSize - body.x1 - 1, top: body.y0, width: body.x1 - body.x0 + 1, height: body.y1 - body.y0 + 1 };
  const crop = { left: Math.max(0, visible.x0 - 3), top: Math.max(0, visible.y0 - 3) };
  crop.width = Math.min(info.width, visible.x1 + 4) - crop.left;
  crop.height = Math.min(info.height, visible.y1 + 4) - crop.top;
  // Removing the long tail must not enlarge the head to refill its former width.
  const crown = pixelBounds(data, info.width, info.height, (r, g, b, a, x, y) =>
    a >= 128 && y < info.height * .65 && b > 150 && g > 60 && b >= g * .98 && b - r > 50);
  if (!crown) throw new Error('sleeping: missing blue crown for consistent character scale');
  const targetCrownHeight = 53;
  const scale = Math.min(target.width / crop.width, target.height / crop.height, targetCrownHeight / (crown.y1 - crown.y0 + 1));
  const width = Math.round(crop.width * scale), height = Math.round(crop.height * scale);
  const destination = { width, height, left: target.left, top: target.top + target.height - height };
  if (!fits(destination)) throw new Error('sleeping: base would clip');
  const pixels = await sharp(source).extract(crop).resize(width, height, { kernel: 'nearest', fit: 'fill' }).ensureAlpha().raw().toBuffer();
  const base = Buffer.alloc(cellSize * cellSize * 4);
  copyPixels(pixels, width, height, base, cellSize, destination.left, destination.top);
  const atlasPng = await sharp(base, { raw: { width: cellSize, height: cellSize, channels: 4 } }).png().toBuffer();
  const { gif, timing } = await encodeSleepingGif(definition, base);
  return { definition, framePngs: [atlasPng], atlasPng, gif, manifest: {
    name: definition.name, ...timing, source: path.relative(root, sourcePath),
    sourceSha256: createHash('sha256').update(source).digest('hex'), sourceSize: [info.width, info.height],
    sourceGrid: [1, 1], frameCount: 1, sourcePoseSequence: [1], registrationMode: 'mirrored-suwudu-sleeping-base',
    runtimeFile: 'shenqing-sleeping-base.png', referenceBody: body, target, crop, crown, targetCrownHeight, scale, destination,
  } };
}

async function preflight(definition) {
  if (definition.name === 'sleeping') return preflightSleeping(definition);
  const sourcePath = path.join(atlasDir, `${definition.name}-source.png`);
  const source = await fs.readFile(sourcePath);
  const metadata = await sharp(source).metadata();
  if (!metadata.hasAlpha || !metadata.width || !metadata.height || Math.abs(metadata.width / metadata.height - 1) > 0.02) {
    throw new Error(`${definition.name}: expected a transparent square 4x4 source sheet`);
  }
  const whole = await sharp(source).ensureAlpha().raw().toBuffer();
  const rowEdges = [0];
  for (let index = 1; index < 4; index++) {
    rowEdges.push(findGutter(whole, metadata.width, metadata.height, 'row', Math.round(index * metadata.height / 4),
      0, metadata.width, definition.name));
  }
  rowEdges.push(metadata.height);
  const columnEdgesByRow = [];
  for (let row = 0; row < 4; row++) {
    const edges = [0];
    for (let column = 1; column < 4; column++) {
      edges.push(findGutter(whole, metadata.width, metadata.height, 'column', Math.round(column * metadata.width / 4),
        rowEdges[row], rowEdges[row + 1], `${definition.name} row ${row + 1}`));
    }
    columnEdgesByRow.push([...edges, metadata.width]);
  }
  const measurements = [];
  for (let index = 0; index < 16; index++) {
    const column = index % 4, row = Math.floor(index / 4);
    const cell = { left: columnEdgesByRow[row][column], top: rowEdges[row] };
    cell.width = columnEdgesByRow[row][column + 1] - cell.left;
    cell.height = rowEdges[row + 1] - cell.top;
    const data = await sharp(source).extract(cell).ensureAlpha().raw().toBuffer();
    measurements.push({ sourcePose: index + 1, cell,
      ...measure(data, cell.width, cell.height, `${definition.name} pose ${index + 1}`,
        { left: column === 0, right: column === 3, top: row === 0, bottom: row === 3 },
        definition.name === 'hit' ? 0.65 : 0.36) });
  }
  const medianHeight = median(measurements.map(frame => frame.crownToHemHeight));
  const requestedScale = targetHeight / medianHeight;
  let scale = requestedScale;
  // Reduce the entire sheet together when any moving effect needs extra room.
  for (const frame of measurements) {
    const { anchor, crop } = frame;
    const limits = [[targetAnchor.x - margin, anchor.x - crop.left],
      [cellSize - margin - targetAnchor.x, crop.left + crop.width - anchor.x],
      [targetAnchor.y - margin, anchor.y - crop.top],
      [cellSize - margin - targetAnchor.y, crop.top + crop.height - anchor.y]];
    for (const [available, extent] of limits) if (extent > 0) scale = Math.min(scale, available / extent);
  }
  // Integer nearest-neighbour dimensions can add one pixel at an edge.
  let attempts = 0;
  while (measurements.some(frame => !fits(placement(frame, scale)))) {
    scale *= 0.999;
    if (++attempts > 1000) throw new Error(`${definition.name}: cannot fit the artwork with an eight-pixel margin`);
  }
  if (!Number.isFinite(scale) || scale <= 0) throw new Error(`${definition.name}: invalid registration scale`);
  const rawFrames = [];
  const registration = [];
  for (const frame of measurements) {
    const destination = placement(frame, scale);
    if (!fits(destination)) throw new Error(`${definition.name} pose ${frame.sourcePose}: output would clip`);
    const crop = { left: frame.cell.left + frame.crop.left, top: frame.cell.top + frame.crop.top,
      width: frame.crop.width, height: frame.crop.height };
    const pixels = await sharp(source).extract(crop)
      .resize(destination.width, destination.height, { kernel: 'nearest', fit: 'fill' })
      .ensureAlpha().raw().toBuffer();
    const output = Buffer.alloc(cellSize * cellSize * 4);
    copyPixels(pixels, destination.width, destination.height, output, cellSize, destination.left, destination.top);
    rawFrames.push(output);
    registration.push({ sourcePose: frame.sourcePose, sourceCell: frame.cell, crop,
      sourceAnchor: { x: frame.cell.left + frame.anchor.x, y: frame.cell.top + frame.anchor.y },
      localAnchor: frame.anchor, crown: frame.crown, body: frame.body, content: frame.content,
      visible: frame.visible,
      sourceOuterEdgeTouches: frame.sourceOuterEdgeTouches,
      hemRows: frame.hemRows, crownToHemHeight: frame.crownToHemHeight, destination });
  }
  // Choose neighboring micro-poses for these new loops. Imagegen's row changes
  // otherwise introduce 3–4px head jumps; this only orders existing RGBA poses.
  const sequence = definition.sourceSequence
    ? definition.sourceSequence.map(frame => frame - 1)
    : [...Array.from({ length: 15 }, (_, index) => index), 0];
  const outputFrames = sequence.map(index => rawFrames[index]);
  const framePngs = [];
  const atlas = Buffer.alloc(cellSize * 4 * cellSize * 4 * 4);
  for (const [index, frame] of outputFrames.entries()) {
    framePngs.push(await sharp(frame, { raw: { width: cellSize, height: cellSize, channels: 4 } }).png().toBuffer());
    copyPixels(frame, cellSize, cellSize, atlas, cellSize * 4, (index % 4) * cellSize, Math.floor(index / 4) * cellSize);
  }
  const atlasPng = await sharp(atlas, { raw: { width: cellSize * 4, height: cellSize * 4, channels: 4 } }).png().toBuffer();
  const { gif, timing } = await encodePreviewGif(definition, outputFrames);
  return { definition, framePngs, atlasPng, gif, manifest: {
    name: definition.name, ...timing,
    source: path.relative(root, sourcePath), sourceSha256: createHash('sha256').update(source).digest('hex'),
    sourceSize: [metadata.width, metadata.height], sourceGrid: [4, 4],
    cellEdges: { rowEdges, columnEdgesByRow, gutterAlphaTolerance: 1, searchRadius: 24 },
    frameCount: 16, sourcePoseSequence: sequence.map(index => index + 1),
    registrationMode: 'lower-hair-hem', targetAnchor, targetHeight, medianCrownToHemHeight: medianHeight,
    normalizedMedianCrownToHemHeight: medianHeight * scale,
    cropPolicy: { visibleAlphaThreshold: 16, padding: 3, preserveRgbaInsideCrop: true },
    requestedScale, scale, margin, registration,
  } };
}

async function archivePrevious() {
  try {
    const existing = await fs.readdir(archiveDir);
    if (existing.some(name => /^shenqing-.*\.png$/.test(name))) return;
    throw new Error(`${archiveDir}: existing archive has no sprite snapshot; refusing to overwrite it`);
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }
  const files = (await fs.readdir(spriteDir)).filter(name => /^shenqing-.*\.png$/.test(name)).sort();
  if (!files.length) throw new Error('No previous Shen Qing sprites found to archive');
  await fs.mkdir(path.dirname(archiveDir), { recursive: true });
  const staging = await fs.mkdtemp(`${archiveDir}-staging-`);
  try {
    for (const name of files) await fs.copyFile(path.join(spriteDir, name), path.join(staging, name));
    await fs.writeFile(path.join(staging, 'snapshot.json'), JSON.stringify({ files }, null, 2) + '\n');
    await fs.rename(staging, archiveDir);
  } catch (error) {
    await fs.rm(staging, { recursive: true, force: true });
    throw error;
  }
}

async function previewHtml(animations, cardDefinitions = definitions) {
  const candidatePreview = cardDefinitions === selected && draftHit;
  const title = candidatePreview ? '沈青 · 受击护心新稿' : '沈青 · 12 套动画';
  const introduction = candidatePreview
    ? '候选稿：向中间收拢，眯眼并把爱心向前、向上举起，挡一下击打。此稿仅供预览，桌宠仍使用已恢复的上一版点击反应。'
    : '待机双手轻开合、红心固定，工作小幅打字；点击反应恢复上一版闭眼举心，睡眠时 ZZZ 轻轻飘动。暂停可同时停住所有动作，并手动查看逐帧动画的全部 16 帧。';
  let candidateLink = '';
  if (!candidatePreview) {
    try { await fs.access(path.join(atlasDir, 'hit-guard-candidate-preview.html'));
      candidateLink = '<p><a href="hit-guard-candidate-preview.html">查看受击护心新稿（尚未启用）</a></p>';
    } catch (error) { if (error.code !== 'ENOENT') throw error; }
  }
  const available = new Map(animations.map(animation => [animation.name, animation]));
  const sleepingSpecs = available.get('sleeping')?.layeredZzz ?? sleepZSpecs;
  const sleepingGlyphs = available.has('sleeping')
    ? await Promise.all(sleepingSpecs.map(async z => {
      const png = await fs.readFile(path.join(spriteDir, `sleeping-z-${z.name}.png`));
      return `<img class="sleep-z" alt="" aria-hidden="true" draggable="false" src="data:image/png;base64,${png.toString('base64')}" style="left:${z.x / 362 * 100}%;top:${z.y / 362 * 100}%;width:${z.w / 362 * 100}%;height:${z.h / 362 * 100}%">`;
    })) : [];
  const cards = cardDefinitions.map(definition => {
    const animation = available.get(definition.name);
    if (!animation) return `<article><h2>${definition.label}</h2><p>尚未导出</p></article>`;
    if (definition.name === 'sleeping') {
      return `<article data-action="sleeping" data-sleeping>
        <h2>睡眠</h2><div class="stage"><div class="sprite sleep-base" role="img" aria-label="沈青睡眠" style="background-image:url('sleeping.png')"></div>${sleepingGlyphs.join('')}</div>
        <p class="counter">分层 ZZZ · 10 秒循环</p><p><a href="sleeping.png">睡姿图</a> · <a href="sleeping-preview.gif">GIF</a></p></article>`;
    }
    const sequence = animation.playbackFrameSequence ?? Array.from({ length: 16 }, (_, index) => index + 1);
    const durations = animation.frameDurationsMs ?? sequence.map(() => animation.intervalMs);
    const seconds = durations.reduce((sum, duration) => sum + duration, 0) / 1000;
    const note = definition.name === 'idle' ? ' · 双手轻开合，红心固定'
      : definition.name === 'working' ? ' · 小幅打字，全程睁眼'
      : definition.name === 'hit' ? ' · 已恢复上一版闭眼举心'
      : definition.name === 'hit-guard-candidate' ? ' · 候选稿，尚未启用' : '';
    return `<article data-action="${definition.name}" data-sequence="${sequence.join(',')}" data-durations="${durations.join(',')}">
      <h2>${definition.label}</h2><div class="stage"><div class="sprite" role="img" aria-label="沈青${definition.label}" style="background-image:url('${definition.name}.png')"></div></div>
      <p class="counter">1 / 16</p><div class="controls"><button data-step="-1">上一帧</button><button data-step="1">下一帧</button></div>
      <p><a href="${definition.name}.png">Sprite sheet</a> · <a href="${definition.name}-preview.gif">GIF</a> · ${seconds} 秒 / 轮${note}</p></article>`;
  }).join('\n');
  return `<!doctype html>
<html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${title}</title><style>
*{box-sizing:border-box}body{margin:0;padding:28px;background:#f4f1e9;color:#252722;font:15px system-ui,sans-serif}h1{font-size:26px;margin:0 0 8px}h2{font-size:17px;margin:0 0 12px}header{max-width:1100px;margin:0 auto 24px}header p{line-height:1.6}button{border:1px solid #b5bcb0;border-radius:7px;background:white;padding:7px 12px;color:inherit;cursor:pointer}button:focus-visible,a:focus-visible{outline:3px solid #568b68;outline-offset:2px}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(250px,1fr));gap:18px;max-width:1400px;margin:auto}article{padding:18px;background:#fffdf7;border:1px solid #d8ddcf;border-radius:12px;text-align:center}.stage{width:242px;max-width:100%;aspect-ratio:1;margin:auto;background-color:#e6e6df;background-image:linear-gradient(45deg,#f7f7f1 25%,transparent 25%),linear-gradient(-45deg,#f7f7f1 25%,transparent 25%),linear-gradient(45deg,transparent 75%,#f7f7f1 75%),linear-gradient(-45deg,transparent 75%,#f7f7f1 75%);background-size:20px 20px;background-position:0 0,0 10px,10px -10px,-10px 0}.sprite{width:100%;height:100%;background-size:400% 400%;background-repeat:no-repeat;image-rendering:pixelated}.counter{font-variant-numeric:tabular-nums;margin:8px}.controls{display:flex;justify-content:center;gap:8px}article p:last-child{font-size:12px;color:#596354}a{color:#2e6544}
.stage{position:relative}.sleep-base{background-size:100% 100%;background-position:0 0}.sleep-z{position:absolute;transform-origin:50% 50%;opacity:0;image-rendering:pixelated;pointer-events:none}
</style><header><h1>${title}</h1><p>${introduction}</p><p>这里循环展示各个动作；实际桌宠的敲打反应只播放一次，自动眨眼等小动作间隔为 60–120 秒。</p>${candidateLink}<button id="toggle" type="button">暂停全部</button></header><main>${cards}</main>
<script>
const cards=Array.from(document.querySelectorAll('[data-action]:not([data-sleeping])')).map(element=>({element,index:0,cursor:0,elapsed:0,sequence:element.dataset.sequence.split(',').map(value=>Number(value)-1),durations:element.dataset.durations.split(',').map(Number)}));
const sleepSpecs=${JSON.stringify(sleepingSpecs)},sleepImages=Array.from(document.querySelectorAll('[data-sleeping] .sleep-z'));let sleepElapsed=0;
function drawSleep(){const t=sleepElapsed/10000;for(let index=0;index<sleepImages.length;index++){const z=sleepSpecs[index],image=sleepImages[index];const opacity=t<z.appear||t>=z.gone?0:t<z.fully?(t-z.appear)/(z.fully-z.appear):t<=z.fade?1:(z.gone-t)/(z.gone-z.fade);const progress=Math.max(0,Math.min(1,(t-z.appear)/(z.arrive-z.appear)));const scale=z.startScale+(z.endScale-z.startScale)*progress;const dx=-(z.startX+(z.endX-z.startX)*progress),dy=z.startY+(z.endY-z.startY)*progress;image.style.opacity=opacity;image.style.transform='translate('+(dx/z.w*100)+'%,'+(dy/z.h*100)+'%) scale('+scale+')'}}
const toggle=document.getElementById('toggle');let playing=!matchMedia('(prefers-reduced-motion: reduce)').matches;
function draw(card){card.element.querySelector('.sprite').style.backgroundPosition=(card.index%4/3*100)+'% '+(Math.floor(card.index/4)/3*100)+'%';card.element.querySelector('.counter').textContent=(card.index+1)+' / 16'}
function setPlaying(value){if(value){for(const card of cards){if(card.sequence[card.cursor]!==card.index){let cursor=card.sequence.indexOf(card.index);if(cursor<0)cursor=card.sequence.findIndex(frame=>frame>card.index);card.cursor=cursor<0?0:cursor;card.index=card.sequence[card.cursor];card.elapsed=0;draw(card)}}}playing=value;toggle.textContent=value?'暂停全部':'播放全部';toggle.setAttribute('aria-pressed',String(value))}
toggle.addEventListener('click',()=>setPlaying(!playing));
for(const card of cards){draw(card);card.element.querySelectorAll('[data-step]').forEach(button=>button.addEventListener('click',()=>{setPlaying(false);card.index=(card.index+Number(button.dataset.step)+16)%16;card.elapsed=0;draw(card)}))}
drawSleep();setPlaying(playing);let previous=performance.now();function tick(now){const delta=Math.min(now-previous,250);previous=now;if(playing){for(const card of cards){card.elapsed+=delta;let changed=false;while(card.elapsed>=card.durations[card.cursor]){card.elapsed-=card.durations[card.cursor];card.cursor=(card.cursor+1)%card.sequence.length;card.index=card.sequence[card.cursor];changed=true}if(changed)draw(card)}sleepElapsed=(sleepElapsed+delta)%10000;drawSleep()}requestAnimationFrame(tick)}requestAnimationFrame(tick);
</script></html>\n`;
}

let previousManifest = { animations: [] };
try {
  previousManifest = JSON.parse(await fs.readFile(manifestPath, 'utf8'));
  if (!Array.isArray(previousManifest.animations)) throw new Error('Invalid v4 registration manifest');
} catch (error) {
  if (error.code !== 'ENOENT') throw error;
}
// All decoding, registration, fit checks and PNG/GIF encoding precede mutations.
const prepared = [];
for (const definition of selected) {
  const result = timingOnly
    ? await preflightTiming(definition, previousManifest.animations.find(animation => animation.name === definition.name))
    : await preflight(definition);
  prepared.push(result);
  console.log(timingOnly
    ? `Timing ${definition.name}: ${result.manifest.playbackFrameSequence.length} playback frames; ${result.manifest.totalDurationMs}ms; GIF delays verified`
    : `Preflight ${definition.name}: ${result.manifest.frameCount} frames; scale ${result.manifest.scale.toFixed(5)}; ${result.manifest.registrationMode}`);
}
if (checkOnly) {
  console.log(`Validated ${prepared.length} sheets; no files changed.`);
} else if (draftHit) {
  const result = prepared[0];
  const name = result.definition.name;
  await fs.writeFile(path.join(atlasDir, `${name}.png`), result.atlasPng);
  await fs.writeFile(path.join(atlasDir, `${name}-preview.gif`), result.gif);
  await fs.writeFile(path.join(atlasDir, `${name}-registration.json`), JSON.stringify(result.manifest, null, 2) + '\n');
  await fs.writeFile(path.join(atlasDir, `${name}-preview.html`), await previewHtml([result.manifest], selected));
  console.log(`${name}: exported proposal only; runtime sprites and active registration unchanged`);
} else {
  const byName = new Map(previousManifest.animations.map(animation => [animation.name, animation]));
  for (const result of prepared) byName.set(result.definition.name, result.manifest);
  const animations = definitions.filter(definition => byName.has(definition.name)).map(definition => byName.get(definition.name));
  const manifest = timingOnly ? { ...previousManifest, animations }
    : { version: 4, cellSize, columns: 4, rows: 4, targetAnchor, animations };
  if (!timingOnly) {
    await archivePrevious();
    await fs.mkdir(spriteDir, { recursive: true });
  }
  for (const result of prepared) {
    const name = result.definition.name;
    if (!timingOnly) {
      for (const [index, png] of result.framePngs.entries()) {
        const filename = name === 'sleeping' ? 'shenqing-sleeping-base.png' : `shenqing-${name}-${String(index + 1).padStart(2, '0')}.png`;
        await fs.writeFile(path.join(spriteDir, filename), png);
      }
      await fs.writeFile(path.join(atlasDir, `${name}.png`), result.atlasPng);
    }
    await fs.writeFile(path.join(atlasDir, `${name}-preview.gif`), result.gif);
    console.log(timingOnly ? `${name}: updated GIF timing; PNG artwork unchanged`
      : `${name}: ${result.manifest.frameCount} RGBA frames at 362x362`);
  }
  await fs.writeFile(manifestPath, JSON.stringify(manifest, null, 2) + '\n');
  await fs.writeFile(path.join(atlasDir, 'preview.html'), await previewHtml(animations));
}

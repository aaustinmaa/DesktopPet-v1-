// Mechanically register imagegen's Shen Qing v4 artwork; never repaint pixels.
// Usage: SHARP_MODULE=/path/to/sharp node Scripts/BuildShenQingV4Atlases.mjs [--check] [idle ...]
// With no action names all twelve sheets are preflighted before any output changes.
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
  { name: 'idle', label: '待机', interval: 170 },
  { name: 'blink', label: '眨眼', interval: 80 },
  { name: 'happy', label: '开心', interval: 150 },
  { name: 'wave', label: '挥手', interval: 100 },
  { name: 'heart', label: '举心', interval: 115 },
  { name: 'working', label: '工作', interval: 100 },
  { name: 'success', label: '成功', interval: 95 },
  { name: 'error', label: '出错', interval: 125 },
  { name: 'sleeping', label: '睡眠', interval: 250 },
  { name: 'reminder', label: '摇铃提醒', interval: 90 },
  { name: 'hit', label: '点击反应', interval: 75 },
  { name: 'question', label: '疑问', interval: 150 },
];
const args = process.argv.slice(2);
const checkOnly = args.includes('--check');
const names = args.filter(arg => arg !== '--check');
if (names.some(name => !definitions.some(definition => definition.name === name))) {
  throw new Error(`Usage: node Scripts/BuildShenQingV4Atlases.mjs [--check] [${definitions.map(d => d.name).join(' ')}]`);
}
const selected = names.length ? definitions.filter(d => names.includes(d.name)) : definitions;
const sharp = require(process.env.SHARP_MODULE || 'sharp');

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

function measure(data, width, height, description, sourceOuterEdges) {
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
    a >= 128 && x >= width * 0.30 && x <= width * 0.70 && y < height * 0.36
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

async function preflight(definition) {
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
        { left: column === 0, right: column === 3, top: row === 0, bottom: row === 3 }) });
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
  const sequence = [...Array.from({ length: 15 }, (_, index) => index), 0];
  const outputFrames = sequence.map(index => rawFrames[index]);
  const framePngs = [];
  const atlas = Buffer.alloc(cellSize * 4 * cellSize * 4 * 4);
  for (const [index, frame] of outputFrames.entries()) {
    framePngs.push(await sharp(frame, { raw: { width: cellSize, height: cellSize, channels: 4 } }).png().toBuffer());
    copyPixels(frame, cellSize, cellSize, atlas, cellSize * 4, (index % 4) * cellSize, Math.floor(index / 4) * cellSize);
  }
  const atlasPng = await sharp(atlas, { raw: { width: cellSize * 4, height: cellSize * 4, channels: 4 } }).png().toBuffer();
  const gif = await sharp(Buffer.concat(outputFrames), {
    raw: { width: cellSize, height: cellSize * 16, channels: 4, pageHeight: cellSize },
  }).gif({ delay: sequence.map(() => definition.interval), loop: 0, dither: 0 }).toBuffer();
  return { definition, framePngs, atlasPng, gif, manifest: {
    name: definition.name, intervalMs: definition.interval,
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

function previewHtml(animations) {
  const available = new Set(animations.map(animation => animation.name));
  const cards = definitions.map(definition => available.has(definition.name)
    ? `<article data-action="${definition.name}" data-interval="${definition.interval}">
      <h2>${definition.label}</h2><div class="stage"><div class="sprite" role="img" aria-label="沈青${definition.label}" style="background-image:url('${definition.name}.png')"></div></div>
      <p class="counter">1 / 16</p><div class="controls"><button data-step="-1">上一帧</button><button data-step="1">下一帧</button></div>
      <p><a href="${definition.name}.png">Sprite sheet</a> · <a href="${definition.name}-preview.gif">GIF</a> · ${definition.interval} ms / 帧</p></article>`
    : `<article><h2>${definition.label}</h2><p>尚未导出</p></article>`).join('\n');
  return `<!doctype html>
<html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>沈青 · 动画预览</title><style>
*{box-sizing:border-box}body{margin:0;padding:28px;background:#f4f1e9;color:#252722;font:15px system-ui,sans-serif}h1{font-size:26px;margin:0 0 8px}h2{font-size:17px;margin:0 0 12px}header{max-width:1100px;margin:0 auto 24px}header p{line-height:1.6}button{border:1px solid #b5bcb0;border-radius:7px;background:white;padding:7px 12px;color:inherit;cursor:pointer}button:focus-visible,a:focus-visible{outline:3px solid #568b68;outline-offset:2px}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(250px,1fr));gap:18px;max-width:1400px;margin:auto}article{padding:18px;background:#fffdf7;border:1px solid #d8ddcf;border-radius:12px;text-align:center}.stage{width:242px;max-width:100%;aspect-ratio:1;margin:auto;background-color:#e6e6df;background-image:linear-gradient(45deg,#f7f7f1 25%,transparent 25%),linear-gradient(-45deg,#f7f7f1 25%,transparent 25%),linear-gradient(45deg,transparent 75%,#f7f7f1 75%),linear-gradient(-45deg,transparent 75%,#f7f7f1 75%);background-size:20px 20px;background-position:0 0,0 10px,10px -10px,-10px 0}.sprite{width:100%;height:100%;background-size:400% 400%;background-repeat:no-repeat;image-rendering:pixelated}.counter{font-variant-numeric:tabular-nums;margin:8px}.controls{display:flex;justify-content:center;gap:8px}article p:last-child{font-size:12px;color:#596354}a{color:#2e6544}
</style><header><h1>沈青 · 12 套动画</h1><p>每套 16 帧。这里将所有动作循环展示，便于比较轮廓与表情；暂停后可逐帧查看。</p><button id="toggle" type="button">暂停全部</button></header><main>${cards}</main>
<script>
const cards=Array.from(document.querySelectorAll('[data-action]')).map(element=>({element,index:0,elapsed:0,interval:Number(element.dataset.interval)}));
const toggle=document.getElementById('toggle');let playing=!matchMedia('(prefers-reduced-motion: reduce)').matches;
function draw(card){card.element.querySelector('.sprite').style.backgroundPosition=(card.index%4/3*100)+'% '+(Math.floor(card.index/4)/3*100)+'%';card.element.querySelector('.counter').textContent=(card.index+1)+' / 16'}
function setPlaying(value){playing=value;toggle.textContent=value?'暂停全部':'播放全部';toggle.setAttribute('aria-pressed',String(value))}
toggle.addEventListener('click',()=>setPlaying(!playing));
for(const card of cards){draw(card);card.element.querySelectorAll('[data-step]').forEach(button=>button.addEventListener('click',()=>{setPlaying(false);card.index=(card.index+Number(button.dataset.step)+16)%16;card.elapsed=0;draw(card)}))}
setPlaying(playing);let previous=performance.now();function tick(now){const delta=Math.min(now-previous,250);previous=now;if(playing){for(const card of cards){card.elapsed+=delta;if(card.elapsed>=card.interval){const steps=Math.floor(card.elapsed/card.interval);card.elapsed%=card.interval;card.index=(card.index+steps)%16;draw(card)}}}requestAnimationFrame(tick)}requestAnimationFrame(tick);
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
  const result = await preflight(definition);
  prepared.push(result);
  console.log(`Preflight ${definition.name}: 16 frames; scale ${result.manifest.scale.toFixed(5)}; crown-to-hem ${result.manifest.normalizedMedianCrownToHemHeight.toFixed(1)}px`);
}
if (checkOnly) {
  console.log(`Validated ${prepared.length} sheets; no files changed.`);
} else {
  const byName = new Map(previousManifest.animations.map(animation => [animation.name, animation]));
  for (const result of prepared) byName.set(result.definition.name, result.manifest);
  const animations = definitions.filter(definition => byName.has(definition.name)).map(definition => byName.get(definition.name));
  const manifest = { version: 4, cellSize, columns: 4, rows: 4, targetAnchor, animations };
  await archivePrevious();
  await fs.mkdir(spriteDir, { recursive: true });
  for (const result of prepared) {
    const name = result.definition.name;
    for (const [index, png] of result.framePngs.entries()) {
      await fs.writeFile(path.join(spriteDir, `shenqing-${name}-${String(index + 1).padStart(2, '0')}.png`), png);
    }
    await fs.writeFile(path.join(atlasDir, `${name}.png`), result.atlasPng);
    await fs.writeFile(path.join(atlasDir, `${name}-preview.gif`), result.gif);
    console.log(`${name}: 16 RGBA frames at 362x362; atlas at 1448x1448`);
  }
  await fs.writeFile(manifestPath, JSON.stringify(manifest, null, 2) + '\n');
  await fs.writeFile(path.join(atlasDir, 'preview.html'), previewHtml(animations));
}

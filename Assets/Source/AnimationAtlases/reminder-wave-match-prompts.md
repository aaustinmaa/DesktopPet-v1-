# Reminder palette and silhouette match

Mode: built-in `image_gen`, transparent RGBA. The sole image reference and edit target was the approved `wave-v3-source.png`. Only the reminder animation was regenerated; the wave artwork and playback remain unchanged.

The revised source is `reminder-v3-source.png`; the normalized 4 × 4 runtime atlas is `reminder-v3.png`. The old broader reminder source/atlas and 16 runtime frames are preserved under `Assets/Archive/AnimationAtlases/suwudu-reminder-before-wave-match` and `Assets/Archive/Sprites/suwudu-reminder-before-wave-match`.

## Prompt

```text
Use case: identity-preserve.
Asset type: SuWuDu desktop pet, transparent 16-frame handbell-ringing sprite sheet.
Input image 1 is the APPROVED WAVING SHEET and is the EDIT TARGET and the sole authoritative reference for silhouette, anatomy, scale, pixel size, palette, face, hair, and clothes.

Primary request: convert ONLY the waving arm/hand into an arm holding and gently ringing a small yellow handbell. Keep every other part of the character EXACTLY as in this approved waving sheet. The current bell version was too wide/stocky and had a different color cast; this replacement must use the waving character itself.
STRICT INVARIANTS: Preserve the same tall slender long-gray-hair silhouette, same narrow head/body width-to-height ratio, same large coarse pixel clusters, same neutral medium-gray hair with square light-gray highlights, same black contour, same cream skin, emerald-green eyes and clothes, lemon-yellow/green crown and side ornament, and exact vivid red heart. Match the wave image's colors directly, without warmer yellow/brown tint, darkening, extra highlights, desaturation, extra shading or gradients. Do not broaden the hair, cheeks, head or torso. Do not shorten the character to make space for the bell. Long hair covers the entire lower body; NO separated legs, NO visible feet underneath, NO gap cutouts around legs. Preserve the original flat hair hem from the waving sheet.

Layout: same 4 columns by 4 rows, exactly 16 frames. Every whole character has the same unchanged body size and position as the supplied wave cells. Keep head, crown, hair, face, red heart and bottom silhouette completely stationary across frames. True transparent background. No text, numbering, borders or grid lines.
Only action: a short GREEN SLEEVE on viewer-RIGHT connects to a compact cream mitten hand. The hand grips the TOP brown handle of a small GOLD/YELLOW handbell. The flared bell cup hangs BELOW the gripping hand, wide rim at its bottom, tiny dark clapper below rim. Keep bell small, about the size of the existing red heart, with dark hard-edged pixel outline, a few flat yellow shades and a cream highlight, same pixel scale as character. Bell stays in the empty space directly right of cheek/chest, never crosses the face or switches hands. Opposite hand remains holding red heart. No long bare forearm or white glove sleeve.
Continuous gentle motion, 16 sequential poses: neutral downward bell, slight outward tilt, medium outward tilt, outward peak; medium outward tilt, slight outward tilt, neutral, slight inward tilt; inward peak, medium inward tilt, slight inward tilt, neutral; small outward rebound, smaller rebound, neutral, neutral matching first frame. Change the wrist and bell only; keep the bell rigid. Two tiny yellow pixel sound ticks appear beside bell at outward and inward peaks only.
Keep all artwork inside cells with clear padding. No shadow, no glow, no checkerboard painted into background, no particles, no redesign. The result must look like the exact approved waving character simply picked up a bell.
```

## Extraction

Run `node Scripts/BuildSuWuDuActionAtlases.mjs reminder-v3` with `sharp` available (or set `SHARP_MODULE`). This updates only the reminder source extraction, 16 runtime frames and the reminder registration entry. It preserves the generated RGBA and applies the same scale to all frames. Reviewed column gutters keep the small bell in its own frame even where the generated first-column poses extend beyond the nominal quarter-width boundary. The normalized output is 1448 × 1448 with 362 × 362 cells. Playback remains 90 ms/frame, with the final frame matching the opening frame.

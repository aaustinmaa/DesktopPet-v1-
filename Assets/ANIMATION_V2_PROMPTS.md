# Animation V2 sprite prompts

Mode: built-in `image_gen`, with `Source/References/v1image.png`, the archived sprite sheet,
and current idle frames used as visible identity/style references.

## Calm idle and blink atlas

```text
Create a 4 × 4 hard-edged pixel-art atlas of the same SuWuDu character.
Frames 1–8 are a seamless calm breathing loop with tiny vertical breathing
and ornament settling, a stable baseline, and absolutely no side-to-side
rocking. Frames 9–16 are a blink cycle. Keep the character identity, scale,
center, baseline, palette, red heart, and silhouette consistent. Use a flat
solid #ff00ff chroma-key background with no labels, grid lines, shadows,
gradients, antialiasing, text, or watermark.
```

Runtime uses frames 1–8 for calm idle and frames 9–16 for the complete
crouch-and-blink animation.

## Wave and heart atlas

```text
Create a 4 × 4 hard-edged pixel-art atlas of the same SuWuDu character.
Frames 1–8 are one smooth friendly wave: only the arm follows a small natural
arc while the body remains centered and stable. Frames 9–16 are one smooth
red-heart pulse: the heart grows subtly over several steps and returns.
Preserve character identity, full height, scale, baseline, palette, and
padding. Use a flat solid #ff00ff chroma-key background with no lateral
swaying, pose jumps, blur, text, labels, shadows, or watermark.
```

## Hammer overlay atlas

```text
Create a 3 × 3 atlas containing nine sequential frames of a playful toy
hammer strike, with no character. The small chunky hammer has a charcoal
head, pale highlight, warm-brown handle, thick black pixel outline, and the
same hard-edged 16-bit pixel style. Move from upper-right wind-up through a
downward swing to a tiny yellow impact star, then a short rebound. Use a flat
solid #ff00ff chroma-key background. No realistic weapon, violence, text,
labels, blur, gradients, shadows, or watermark.
```

## Success, error, and reminder atlases

Each feedback state uses its existing static sprite as the primary identity
reference and a separate 4 × 4 atlas:

```text
Success: create a seamless 16-frame celebration loop. Ease from a tiny
anticipation into both arms lifting, reveal the three yellow sparkles in
stages, hold a joyful peak, then settle smoothly. Keep the body centered and
avoid lateral rocking, squash/stretch, or sudden pose jumps.
```

```text
Error: create a seamless 16-frame unmistakable big-cry loop using the original
static error sprite as the authoritative slim-body reference. Squeeze both
eyes shut, open the mouth in a small cry, and grow two broad, continuous blue
tear streams from the eyes into a dramatic peak before drawing them back.
Use only a subtle vertical sobbing motion; keep the narrow hood, compact body,
red heart, baseline, and proportions stable. Do not add isolated tear drops,
lateral rocking, body widening, or abrupt pose jumps.
```

```text
Reminder: create a seamless 16-frame alert loop. Keep the character nearly
motionless while the rigid bell swings through several intermediate angles
with natural follow-through. Stage the yellow sound marks in and out, then
settle smoothly. Do not deform the bell or sway the body.
```

All three atlases preserve the SuWuDu identity, palette, scale, baseline, and
padding, and use a flat #ff00ff chroma-key background without grid lines,
labels, shadows, blur, antialiasing, text, or watermark.

## Local processing

The active generated source and transparent atlases are stored in
`Assets/Source/AnimationAtlases`. Pixel-art chroma removal intentionally uses a hard
matte with no despill so the red heart remains unchanged. Runtime frames are
reproducibly extracted with:

```powershell
.\Scripts\ExtractAnimationAtlases.ps1
```

The extraction script writes only current runtime frames to `Assets/Sprites`.
Superseded V2 frames remain available under `Assets/Archive/Sprites`.

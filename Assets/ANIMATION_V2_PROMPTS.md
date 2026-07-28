# Animation V2 sprite prompts

Mode: built-in `image_gen`, with `v1image.png`, the existing sprite sheet,
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

Runtime uses frames 1–8. Blinking combines the stable V2 idle poses with the
existing full-height closed-eye sprite so that the character never crouches.

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

## Local processing

The generated source and transparent atlases are stored in
`Assets/AnimationAtlases`. Pixel-art chroma removal intentionally uses a hard
matte with no despill so the red heart remains unchanged. Runtime frames are
reproducibly extracted with:

```powershell
.\Scripts\ExtractAnimationAtlases.ps1
```

The extracted, non-destructive V2 frames are stored beside the original
sprites under `Assets/Sprites` with `idle-v2-*`, `wave-v2-*`, `heart-v2-*`,
and `hammer-v2-*` names.

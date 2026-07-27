# Sprite generation prompt

Mode: built-in `image_gen`, using `v1image.png` as the visible identity/style reference.

```text
Use case: stylized-concept
Asset type: production sprite sheet for a small Windows desktop pet
Primary request: Create a crisp pixel-art sprite sheet based on the visible reference image. Preserve the same single character identity: a cute dark charcoal-gray rounded capsule/slime creature with a thick black pixel outline, tiny pale face peeking from the lower-right, neon green and lemon-yellow accents, and a bright red pixel heart held at the front. Create exactly 12 distinct animation frames arranged in a perfectly aligned 4 columns by 3 rows grid: idle 1, idle 2, blink, happy bounce; working/typing, question/confused, success/celebrate, error/sad; sleeping, reminder/bell attention, waving, heart pulse. Each cell must contain one full character, centered at the same scale and baseline with generous padding. Keep silhouette and costume details consistent across every frame. Pixel blocks must be hard-edged with no antialiasing, no blur, no gradients, no lighting, no shadows.
Input images: Image 1 is the identity and style reference; faithfully preserve its recognizable silhouette, colors, face placement, and red heart.
Scene/backdrop: perfectly flat solid #ff00ff chroma-key background, uniform in every pixel, no grid lines, no labels, no texture.
Style/medium: polished 16-bit pixel art with a limited palette and large square pixels.
Composition/framing: exact 4x3 contact sheet, equal-size cells, consistent registration and scale.
Constraints: one character per cell, exactly 12 frames, no text, no captions, no icons outside the character, no watermark, no cast shadow; do not use #ff00ff anywhere in the character.
Avoid: smooth vector curves, realistic rendering, extra limbs, changing identity, cropped pixels, inconsistent scale, white background.
```

The generated magenta background was removed locally with the imagegen skill's chroma-key helper. The transparent 4 × 3 result is `sprite-sheet.png`; runtime frames are under `Sprites`.

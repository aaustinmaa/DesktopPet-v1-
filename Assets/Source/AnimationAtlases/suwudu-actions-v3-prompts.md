# SuWuDu wave and reminder v3

Mode: built-in `image_gen`, transparent RGBA output. The user selected the two 4 × 4 sheets from the second generation round. The later 4 × 2 reminder experiment was rejected because it exposed distinct legs/feet; it is not used or stored in the project. Preserve the long-hair silhouette hiding the lower body in future revisions.

The wave still uses the selected `wave-v3-source.png`. The original reminder described below is preserved in `Assets/Archive/AnimationAtlases/suwudu-reminder-before-wave-match`; its active replacement follows the wave's narrower silhouette and palette, with its prompt in `reminder-wave-match-prompts.md`. Active originals remain unmodified imagegen output. Their normalized runtime atlases are `wave-v3.png` and `reminder-v3.png` (1448 × 1448, 4 × 4 cells of 362 × 362).

## Generation prompts

The reference for the initial generation was `../../Sprites/idle-open-close-v5-01.png`. Each revision used its own first-round generated sheet as the edit target.

### Wave initial prompt

```text
Use case: identity-preserve
Asset type: production pixel-art animation sprite sheet for SuWuDu desktop pet.
Input image 1 is the current approved character and exact style reference. Preserve this same small chibi person with very long dark gray hair, green-yellow tiny crown, green/white/yellow round hair ornament on viewer-left, pale face, green eyes, tiny dark green clothes, red heart in front of chest. This is a person with hair, NOT a blob or ghost.
Primary request: redraw a polished, continuous friendly waving animation. Exactly 16 frames in a perfectly regular 4 columns x 4 rows square grid, read left-to-right, top-to-bottom. Image target 2048x2048, each cell 512x512, no visible grid. Same full character scale and registration in all cells, body center around x=256 of each cell, crown top at y=65, foot baseline y=440, generous clear margins.
Action: ONLY the arm on viewer-RIGHT waves. The other hand holds the red heart. Clearly visible pale open mitten hand attached to a short green sleeve and connected forearm; no extra fingers or arms. Frame 1 relaxed hand next to heart; 2 elbow out; 3 forearm half up; 4 hand beside cheek; 5 palm high angled outward; 6 wrist swings inward; 7 palm high inward; 8 wrist swings outward; 9 palm high outward; 10 wrist swings inward; 11 palm high inward; 12 palm swings outward; 13 hand lowers beside cheek; 14 elbow lowers; 15 hand almost rests; 16 relaxed pose matching frame 1. Make each transition readable and gentle, no teleport between left/right arms. Stable head, crown, hair, face, heart, torso, feet; zero body bob, rotation, zoom, or reshaping.
Style: match the reference's chunky hard-edged low-resolution pixel art, large square pixel clusters, restrained gray/green/yellow/red palette, dark pixel contour, tiny cream highlights. Keep the same proportions and facial placement. No smoothing or painted gradients.
Background: genuine transparent alpha. No shadow or ground. No checkerboard painted into artwork. No text, numbering, grid lines, watermark, particles, floating icons, motion streaks or extra characters. Never crop the hand, hair or feet.
```

### Wave selected revision prompt

```text
Use case: identity-preserve. Edit the supplied 4x4 waving pixel-art sprite sheet. Preserve exact same SuWuDu character identity, original chunky pixel style, palette, body, crown, hair ornament, red heart and green clothes. Make a clean production 16-frame animation.
ONLY CHANGE THE WAVING RIGHT-SIDE ARM AND HAND. Stable unchanged head, face, hair, heart, legs, size and baseline in all frames.
Exactly 4 columns by 4 rows, equal-sized cells, transparent background. No labels. Body fit around 72% of each cell height and generous margins. Right-side elbow remains at chest level, forearm rotates at elbow to wave near head level, pale mitten hand open and palm outward. Make a visibly high friendly greeting, never punching, pointing or reaching straight sideways. One opposite hand holds heart throughout.
Ordered action by rows:
Row 1 four frames: hand resting by heart; elbow bends and hand rising; hand level with chin; hand level with eye.
Row 2 four frames: raised hand beside face at eye level tilted outward; raised hand tilted slightly inward; raised hand tilted inward toward crown; raised hand tilted slightly outward.
Row 3 four frames: raised hand tilted outward; raised hand tilted slightly inward; raised hand tilted inward toward crown; raised hand tilted slightly outward. Keep hand high for every frame in rows 2 and 3.
Row 4 four frames: hand lowers to chin; hand lowers to chest; hand almost returns to heart; hand rests by heart same as first frame.
No arms on viewer-left. No floating or detached hands. No extra fingers. No stray colored outline halo. True transparent alpha. Sharp pixel blocks, no blur, no antialias, no shadow, no outlines outside the original dark pixel contour.
```

### Reminder initial prompt

```text
Use case: identity-preserve
Asset type: production pixel-art animation sprite sheet for SuWuDu desktop pet.
Input image 1 is the current approved character and exact style reference. Preserve this same small chibi person with very long dark gray hair, green-yellow tiny crown, green/white/yellow round hair ornament on viewer-left, pale face, green eyes, tiny dark green clothes, red heart in front of chest. This is a person with hair, NOT a blob or ghost.
Primary request: redraw a polished continuous handbell-ringing animation used for water and rest reminders. Exactly 16 frames in a perfectly regular 4 columns x 4 rows square grid, read left-to-right, top-to-bottom. Image target 2048x2048, each cell 512x512, no visible grid. Same full character scale and registration in every cell, body center around x=256 of each cell, crown top at y=65, foot baseline y=440, generous clear margins.
Action: the visible arm on viewer-RIGHT holds a small rigid golden yellow handbell with a short brown handle, flared dark-outlined bell cup, bright cream highlight, and visible small clapper. The hand grips the handle, never the rim. Other hand remains on the red heart. Arm raised beside face and bell swings from the wrist in a clear graceful left-right pendulum arc. Keep the bell same rigid shape/size, redraw its tilt and clapper consistently. Sixteen sequential bell angles: neutral 0, +15, +30, +40, +30, +15, 0, -20, -35, -40, -30, -15, 0, +15, +10, 0 degrees. Angle extremes must visibly differ; arm connected to body in every frame. Frames 4-5 and 9-10 have just two tiny golden pixel sound ticks near the bell; other frames no ticks. Head, crown, hair, face, heart, torso and feet stay still and same scale. First/last pose match seamlessly. No shrinking bell, multiplying props, flying bell, extra hand, body swaying or squash/stretch.
Style: match the reference's chunky hard-edged low-resolution pixel art, large square pixel clusters, restrained gray/green/yellow/red palette, dark pixel contour, tiny cream highlights. Keep the same proportions and facial placement. No smoothing or painted gradients.
Background: genuine transparent alpha. No shadow or ground. No checkerboard painted into artwork. No text, numbering, grid lines, watermark, extra characters. Never crop bell, hair or feet.
```

### Reminder selected revision prompt

```text
Use case: identity-preserve. Edit the supplied 4x4 bell animation sprite sheet. Preserve exact same SuWuDu chibi character identity, original chunky pixel style, palette, dark gray long hair, green crown and hair ornament, red heart and green clothes. Correct the handbell and arm continuity in ALL 16 frames.
Critical correction 1: the waving/ringing arm is ALWAYS on VIEWER-RIGHT of the body. In row 3 cells 1 and 2 move the bell and its gripping hand back to viewer-RIGHT, same side as all other frames. No bell can ever cross the face or appear on viewer-left.
Critical correction 2: draw a real handbell hanging DOWN from its handle, not an upside-down goblet. The small cream hand grips a short dark brown handle ABOVE the golden bell cup. Bell has narrow top shoulder, golden domed/flared cup expanding toward its WIDE LOWER RIM, a black opening beneath rim, and a tiny dark clapper below. The rim is ALWAYS at the lower free end away from the gripping hand. The hand and bell remain connected.
Exactly 16 frames in 4 columns x4 rows equal grid, all whole character and full bell inside cells. Body height 72% of each cell with generous margin. Identical stationary body position, size, hair, head, crown, face, heart and feet in every frame. Only wrist and forearm on viewer-right rotate; rigid hanging bell pivots left and right about the gripping hand, next to the face. Bell stays right of character at all times, including inward tilt; it does NOT switch hand.
Swing sequence by row:
Row 1 bell hangs vertical; tilted 15 degrees outward; tilted 30 outward; tilted 40 outward.
Row 2 tilted 30 outward; tilted 15 outward; vertical; tilted 15 inward while remaining right of face.
Row 3 tilted 30 inward; tilted 40 inward; tilted 30 inward; tilted 15 inward. All four bells remain VIEWER-RIGHT.
Row 4 vertical; slight outward rebound 15 degrees; slight rebound 8 degrees; vertical matching first frame.
Only 2 tiny yellow sound ticks near bell at swing extremes, no music notes.
Transparent alpha background. No text, labels, grid lines, shadow, blur, gradients, halo or extra outline. Preserve large crisp square pixel clusters.
```

## Registration and playback

Run `node Scripts/BuildSuWuDuActionAtlases.mjs` from the repository with `sharp` installed, or set `SHARP_MODULE` to an existing sharp package path. This rebuilds only these two actions. It retains source RGBA, uses nearest-neighbor sampling, applies one scale to each sheet, and aligns the crown rather than centering on a moving hand or bell. It makes no masks, no new leg cutouts, and no painted changes.

`sourcePoseSequence` and crop/placement coordinates are recorded in `suwudu-actions-v3-registration.json`. Waving reuses its rise in reverse for a smooth return, and the reminder ends on its opening pose. Both final atlases have 16 frames; Windows and Mac use 100 ms for waving and 90 ms for reminders. The existing PowerShell `ExtractAnimationAtlases.ps1` also slices the normalized atlases with the fixed-grid extractor, without resizing or recentering them.

Open `suwudu-actions-v3-preview.html` for playback, frame stepping, speed controls, and light/dark/checker backgrounds. Prior v2 frames and source atlases are retained under `Assets/Archive/Sprites/suwudu-actions-v2` and `Assets/Archive/AnimationAtlases/suwudu-actions-v2`.

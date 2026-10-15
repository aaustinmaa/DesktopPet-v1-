# Asset structure

Every file under `Assets` is classified by
[`asset-classification.json`](asset-classification.json) as either `used` or
`unused` for the shipped application.

- `used`: `app.ico` and every PNG in `Sprites`. These are runtime assets and
  are the only asset files allowed in the installer payload.
- `unused`: source artwork, archived artwork, prompts, references, and asset
  documentation. They remain in the repository for development but must never
  be copied into the installer.

The installer build validates that every asset matches exactly one category.
It also fails when a used asset is missing from the development output or an
unused asset appears there.

The folders are organized by purpose rather than by filename version.

```text
Assets/
|-- Sprites/                    Runtime images loaded by the application
|-- Source/
|   |-- AnimationAtlases/       Active atlases that regenerate runtime frames
|   |-- AppIcon/                Editable app-icon source
|   |-- References/             Current visual references and prototypes
|   `-- Sleeping/               Source and intermediate sleeping artwork
`-- Archive/
    |-- AnimationAtlases/       Superseded atlas versions
    |-- References/             Historical sprite sheets and references
    `-- Sprites/                Superseded or currently unused runtime frames
```

## Rules

- `Sprites` contains only files referenced by the current application.
- `Source` contains files required to regenerate or visually maintain current
  runtime assets.
- `Archive` is intentionally retained for comparison and possible future reuse.
  Archived files are not copied into development or installer output.
- Do not delete archived artwork merely because it is not currently used.
- When a new animation replaces an old one, move the old runtime frames and
  source atlas into `Archive` instead of leaving them in `Sprites`.

## Regeneration

```powershell
.\Scripts\BuildStableWorkingAtlas.ps1
.\Scripts\ExtractAnimationAtlases.ps1
.\Scripts\ExtractShenQingAtlases.ps1
.\Scripts\BuildSleepingLayers.ps1
```

These scripts read active source art from `Source` and write only current
runtime images to `Sprites`. The stable working-atlas script must use fixed
362-by-362 cells so the character and laptop pixels are never rescaled or
recentered between frames.

Shen Qing's current artwork is in `Source/AnimationAtlases/shenqing-v4`.
`approved-design.png` preserves the approved design board; `identity-reference.png`
is its neutral pose. The character retains his blue crown, green side ornament,
gray hair and amber eyes, with one continuous flat hair/robe hem and no exposed feet.

Eleven states have independent 4-by-4 sheets of sixteen frames: idle, blink,
happy, wave, heart, working, success, error, reminder, hit and question.
Happy no longer borrows a Success frame. These normalized `{action}.png` files
are 1448 by 1448, containing fixed 362-by-362 cells; the 176 runtime frames retain
the `Sprites/shenqing-{action}-{01..16}.png` naming convention.
Sleeping instead uses the single 362-by-362 `sleeping.png`, copied to
`Sprites/shenqing-sleeping-base.png`. It reuses SuWuDu's three separate
`sleeping-z-{small,medium,large}.png` layers and their ten-second choreography.
The layers' positions and horizontal movement are mirrored for Shen Qing's
left-facing pose; the Z glyph images themselves remain unflipped.

Run `node Scripts/BuildShenQingV4Atlases.mjs` with Node and `sharp` available.
`SHARP_MODULE` may point to an existing sharp installation. The script preserves
generated RGBA, applies one nearest-neighbor scale per sheet, and registers the
lower hair hem so local head acting survives without shifting the baseline.
The closing frame repeats the opening frame. Previous runtime frames are saved
in `Archive/Sprites/shenqing-before-v4` before replacement.
`ExtractShenQingAtlases.ps1` can also slice the eleven normalized v4 sheets
without resizing and copy the single sleeping base.
The superseded sixteen-frame sleeping sprites and source sheet are retained in
`Archive/Sprites/shenqing-sleeping-before-layers` and
`Archive/AnimationAtlases/shenqing-sleeping-before-layers`; the latter also keeps
the previous normalized sleeping sheet and its exact prompt.

Open `Source/AnimationAtlases/shenqing-v4/preview.html` to play or step through
all twelve animations. Sheet animations also have a looping `{action}-preview.gif`.
Shen Qing's idle gently opens and closes both hands at 170 ms per frame, keeping
the red heart fixed at the chest. Working uses subtle typing at 120 ms per frame.
Both keep the eyes open throughout and use continuous small movements without
long frozen holds. Waving also keeps the eyes open and uses 120 ms per frame.
Blinking is a separate action at
80 ms per frame; automatic idle gestures remain 60–120 seconds apart.
The exported loops arrange neighboring generated poses into gradual movement;
`sourcePoseSequence` records this order without repainting the source artwork.
Reminder playback uses 160 ms per frame. The hit reaction follows SuWuDu's
closed-eye dip and rebound over all sixteen frames in 1.06 seconds; the lowest
poses, frames 8 and 9, span the hammer's 430 ms impact. Repeated idle strikes
restart both the hammer and Shen Qing's reaction together.
Run `node Scripts/BuildShenQingV4Atlases.mjs --timing-only` to refresh GIFs,
the preview and timing metadata from existing sprites without rewriting any PNGs.
The built-in imagegen sheet sources and exact prompts are saved as
`{action}-source.png` and `{action}-prompt.txt`. Sleeping uses
`sleeping-base-source.png` and `sleeping-prompt.txt` for its static base instead.
`prompt-base.txt` records the shared identity and flat-base constraints.
`registration.json` records the crop, scale, frame sequence and timing used for
export.

The older v3 artwork, prompts and outline masks remain historical references.
The legacy `BuildShenQingAtlases.py` pipeline is for those eight-frame sheets;
do not run it to rebuild current v4 assets or apply its v3 erasure masks to them.

## SuWuDu wave and reminder v3

The approved `wave-v3-source.png` and `reminder-v3-source.png` are both 4-by-4
imagegen sheets. Preserve their long-hair silhouette covering the lower body;
the later eight-pose reminder experiment with exposed legs was rejected.
The current wave adds a head dip, wink, smiling eyes and two small wrist waves.
Its acting prompt is in `Source/AnimationAtlases/wave-cute-prompts.md`; open
`Source/AnimationAtlases/wave-v3-preview.gif` for a looping preview.
The current reminder was redrawn directly from the approved wave sheet to match
its narrow silhouette and neutral-gray/green palette. Its prompt is recorded in
`Source/AnimationAtlases/reminder-wave-match-prompts.md`; the previous broader
reminder is preserved in the `suwudu-reminder-before-wave-match` archive folders.

Run `node Scripts/BuildSuWuDuActionAtlases.mjs` with Node and `sharp` available
to rebuild only these two animations. `SHARP_MODULE` can point to an existing
sharp installation. Append `wave-v3` or `reminder-v3` to rebuild only that action
and its registration entry. The script preserves generated RGBA and applies one
nearest-neighbor scale per sheet. Wave registration fixes the lower hair hem to
preserve the head acting; reminder registration fixes the crown.
It emits 16 fixed 362-by-362 frames and a 1448-by-1448 atlas per action.
Windows and Mac play waving at 100 ms per frame and reminders at 90 ms.
The PowerShell extractor also slices the final atlases without rescaling.

Open `Source/AnimationAtlases/suwudu-actions-v3-preview.html` to play or step
through the animations. Prompts and registration data are saved alongside it.
Superseded v2 sources and frames are preserved in the `suwudu-actions-v2`
subfolders under `Archive/AnimationAtlases` and `Archive/Sprites`.

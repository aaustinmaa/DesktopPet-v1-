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

All twelve states have independent 4-by-4 sheets of sixteen frames: idle, blink,
happy, wave, heart, working, success, error, sleeping, reminder, hit and question.
Happy no longer borrows a Success frame. Each normalized `{action}.png` is
1448 by 1448, containing fixed 362-by-362 cells; the 192 runtime frames retain
the `Sprites/shenqing-{action}-{01..16}.png` naming convention.

Run `node Scripts/BuildShenQingV4Atlases.mjs` with Node and `sharp` available.
`SHARP_MODULE` may point to an existing sharp installation. The script preserves
generated RGBA, applies one nearest-neighbor scale per sheet, and registers the
lower hair hem so local head acting survives without shifting the baseline.
The closing frame repeats the opening frame. Previous runtime frames are saved
in `Archive/Sprites/shenqing-before-v4` before replacement.
`ExtractShenQingAtlases.ps1` can also slice the normalized v4 sheets without resizing.

Open `Source/AnimationAtlases/shenqing-v4/preview.html` to play or step through
all twelve animations. Each action also has a looping `{action}-preview.gif`.
Shen Qing now spends most of each idle/work cycle holding an open-eyed pose:
idle lasts 20.32 seconds and working lasts 28.96 seconds. Closed-eye frames stay
brief, and working skips pose 15's additional blink. The standalone blink keeps
its original 80 ms frame timing; automatic idle gestures occur every 60–120 seconds.
Other actions use slower playback without changing the artwork.
Run `node Scripts/BuildShenQingV4Atlases.mjs --timing-only` to refresh GIFs,
the preview and timing metadata from existing sprites without rewriting any PNGs.
The built-in imagegen source images and exact prompts are saved as
`{action}-source.png` and `{action}-prompt.txt`; `prompt-base.txt` records the
shared identity and flat-base constraints. `registration.json` records the
crop, scale, frame sequence and timing used for export.

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

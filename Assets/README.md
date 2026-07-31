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
.\Scripts\BuildSleepingLayers.ps1
```

These scripts read active source art from `Source` and write only current
runtime images to `Sprites`. The stable working-atlas script must use fixed
362-by-362 cells so the character and laptop pixels are never rescaled or
recentered between frames.

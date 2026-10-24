# Grade

Grade is a native iOS photo editor for making your own photos look cinematic. Pick a photo, tap a preset such as **Neon Nights** or **Teal & Orange**, fine-tune it, compare before and after, and save the result to your camera roll.

The app has no login, no account, no server and no analytics. Everything runs on your phone.

- **Presets:** 20 looks in five groups (Cinematic, Moody, Film, Vintage, Black & White), each with a strength slider. They are defined as data in `Grade/Config/Presets.json`.
- **Adjust:** 14 sliders (exposure, contrast, highlights, shadows, warmth, tint, saturation, vibrance, fade, night sky, glow, sharpen, vignette, grain) that apply on top of the chosen preset.
- **My Looks:** save the current preset, strength and adjustments as your own look and reuse it on other photos. The look also stays selected when you open the next photo, so a series can be edited the same way.
- **Before / after:** hold the photo to see the original, or turn on compare mode and drag the divider.
- **Saving:** Save asks whether to **Save as New Photo** (a separate HEIC copy; the original is untouched) or **Replace Original** (the edit is saved onto the library photo, like the Photos app's own Edit, and Photos keeps the original so **Edit → Revert** brings it back). New photos need only *add-only* access; Replace Original asks for full access the first time it's used. Photos with a removed background are saved as new transparent PNGs. Date, camera and location metadata are kept. Photos are opened with the system picker, which needs no permission.
- **Privacy:** no network access. Saved looks are stored as JSON in Application Support. The app is designed for the "Data Not Collected" privacy label.

## How the looks work

Everything is built from Core Image's built-in filters in `Grade/Rendering/FilterChain.swift`, applied in two stages:

1. **Linear light:** exposure, white balance (warmth and tint) and glow. Glow is a halation effect: bright areas such as street lights bleed a soft halo.
2. **Perceptual (gamma) space:** tone curve (fade, highlights, shadows), contrast, saturation, vibrance, split toning (a colour wash in the shadows and another in the highlights), night sky (a cool gradient that darkens the top of the frame), sharpening, vignette and film grain.

All sizes (glow radius, grain, vignette) are relative to the photo's short side, so the 2048 px preview you edit looks the same as the full-resolution photo that gets saved.

Neon Nights recreates the *grade* of a night shot: darker exposure, a cool teal cast in the shadows, warm orange highlights, a darkened sky, glowing lights, vignette and grain. It can't add things that aren't in the photo (such as lit windows or street lamps that are switched off).

## Building

### Without a Mac (GitHub Actions)

Every push runs `.github/workflows/ci.yml` on a GitHub-hosted macOS runner. The workflow:

1. generates the Xcode project with XcodeGen
2. builds the app and runs the unit and UI tests on an iPhone simulator
3. pushes a report to the **`ci-reports`** branch, containing the build summary (errors and warnings), test results and simulator screenshots from the UI tests, including one screenshot of every preset on the demo photo

### Trying it in a browser (no Mac, no iPhone setup)

Each CI run also saves a simulator build at `Grade-simulator.zip` on the `ci-reports` branch:

1. Download it from https://github.com/jondoesflow/Photoeditor/raw/ci-reports/Grade-simulator.zip
2. Upload it at https://appetize.io/upload and choose iOS
3. Start it with the launch argument `-GradeDemo` to open the demo photo (the simulator has few photos of its own)

### On your iPhone (TestFlight, no Mac)

`.github/workflows/testflight.yml` archives, signs and uploads a build to TestFlight from a GitHub-hosted Mac. You run it from the Actions tab with **Run workflow**, or by pushing to the `testflight` branch. It needs four repository secrets: `APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_KEY_P8`. The workflow file explains each one. You also need an app record in App Store Connect with the bundle ID `com.jondoesflow.grade`.

### On a Mac

```bash
brew install xcodegen
xcodegen generate
open Grade.xcodeproj
```

You need Xcode 26 or later. To run on your own iPhone, select your team under Signing & Capabilities.

## Project layout

```
project.yml              XcodeGen spec (iOS 18.0+, Swift 6, strict concurrency)
Grade/
  App/                   GradeApp (launch arguments), EditorModel (state, rendering, saving, My Looks)
  Config/                Presets.json
  Models/                Parameter, Recipe, Tone, Preset, PresetLibrary
  Rendering/             FilterChain (recipe → Core Image graph), PhotoRenderer (actor: decode, preview,
                         thumbnails, export), ExportMetadata
  Saving/                PhotoSaving protocol, PhotoLibrarySaver (add-only), DemoSaver
  Storage/               LookStore (saved looks as on-device JSON)
  UI/                    Editor, compare canvas, preset strip, adjust panel, empty state
  Demo/DemoPhoto.jpg     Sample photo for UI tests (excluded from Release builds)
GradeTests/              Swift Testing unit tests (filter maths on real pixels, recipes, presets, model)
GradeUITests/            XCUITest flows with screenshots
scripts/                 CI helpers (simulator picker, build summary)
CHECKS.md                What was tested, how, and what couldn't be
```

## Adding or changing presets without code

Each preset in `Presets.json` has an `id`, a `name`, a `category` and a `recipe`. A recipe lists only the settings it changes. Every value is normalised so that 0 means "no change":

| Setting | Range | Setting | Range |
|---|---|---|---|
| `exposure` | −1…1 (±1.5 EV) | `vibrance` | −1…1 |
| `contrast` | −1…1 | `fade` | 0…1 |
| `highlights` | −1…1 | `skyDarken` | 0…1 |
| `shadows` | −1…1 | `glow` | 0…1 |
| `warmth` | −1…1 | `sharpen` | 0…1 |
| `tint` | −1…1 (+ is magenta) | `vignette` | 0…1 |
| `saturation` | −1…1 (−1 is black & white) | `grain` | 0…1 |

`shadowTone` and `highlightTone` take a `color` (`"#RRGGBB"`) and a `strength` (0…1).

Unknown keys and out-of-range values are rejected, and the unit tests load the file, so a typo fails CI instead of silently doing nothing.

## Launch arguments (for testing)

| Argument | Effect |
|---|---|
| `-GradeDemo` | Opens the bundled demo photo; saving goes to memory instead of Photos, and saved looks are kept in a temporary folder |
| `-GradeEmpty` | With `-GradeDemo`, starts with no photo (the first-launch screen) |
| `-GradePreset <id>` | With `-GradeDemo`, starts with that preset selected |

## Credits

Demo photo by Tim Stief on [Unsplash](https://unsplash.com/photos/uzBiLWpjQEQ), used under the Unsplash License.

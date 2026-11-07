# Lisse

Lisse is a macOS menu-bar utility that makes mouse-wheel scrolling glide, and lets the wheel use its own direction from the trackpad.

It needs macOS 13 or later. The first time it opens, grant Accessibility access so Lisse can read and rewrite mouse-wheel events. Trackpad scrolling is left alone.

## Preferences

- **Precise, Balanced, and Soft glide** presets. Soft glide uses a longer, gentler easing curve, consistent across display refresh rates.
- **Pause / Enable** at the top of Settings. The **Try for 30 seconds** action automatically returns to paused.
- **Appearance** offers System, Light, or Dark mode, six accent colors, a custom color picker, and optional preview animation.

- **Smooth scrolling** for the vertical axis, the horizontal axis, or both.
- **Step** is the smallest distance applied to one wheel notch.
- **Speed** multiplies that distance.
- **Duration** controls how long the glide takes. A higher value eases out more slowly.
- **Simulate trackpad** posts the glide with trackpad-style scroll phases and locks duration at 4.75.
- **Direction** can reverse vertical and horizontal scrolling separately.
- **While held:** Option accelerates by 5×, Shift swaps the vertical wheel onto the horizontal axis, and Command pauses smoothing. Each shortcut can be changed or turned off.
- **Exceptions** are per-application profiles. An app can inherit the global settings or replace them. Turn on “only the applications listed below” to leave every other app untouched.
- **Launch at login** registers Lisse with the system login items.

The menu-bar icon can be hidden. Open Lisse again and the icon and preferences come back.

## Build

Open `Lisse.xcodeproj` in Xcode and run the Lisse scheme, or:

```bash
xcodebuild -scheme Lisse -configuration Debug build
```

With the macOS Command Line Tools installed, you can also build a universal app without opening Xcode:

```bash
scripts/build-app.sh
scripts/test-scroll-delivery.sh
```

The build script writes `build/Lisse.app` and `build/Lisse.zip`. Set `LISSE_SDK` to choose another installed SDK. The scroll checks do not install event taps or post events to macOS.

For a settings-only launch with scrolling paused:

```bash
open build/Lisse.app --args --settings-only
```

The master icon is in `Design/Lisse-Icon-Master.png`; app-size exports are in the asset catalog.

Button remapping and Logitech device features are not part of Lisse.

## Releases

Every new version is published on [GitHub Releases](https://github.com/shrotshahariar/Lisse/releases). Update the version and build number in the Xcode project, add release notes in `releases/vVERSION.md`, commit the changes, and push a matching tag:

```bash
git tag v1.1
git push origin main v1.1
```

The Release Lisse workflow runs scroll regression checks, builds both Mac architectures, verifies the archive, and publishes `Lisse.zip`. A failed run can be retried from Actions with its existing version tag. Published versions are never overwritten.

For local updates, keep one installed copy at `/Applications/Lisse.app`. Verify the new release before moving older Lisse app bundles to Trash; preserve preferences, source code, and ZIP archives. Launch the installed copy with `--settings-only` during replacement so scrolling stays paused.

Release builds are ad-hoc signed and are not notarized.

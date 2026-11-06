# Lisse

Lisse is a macOS menu-bar utility that makes mouse-wheel scrolling glide, and lets the wheel use its own direction from the trackpad.

It needs macOS 13 or later. The first time it opens, grant Accessibility access so Lisse can read and rewrite mouse-wheel events. Trackpad scrolling is left alone.

## Preferences

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

Button remapping and Logitech device features are not part of Lisse.

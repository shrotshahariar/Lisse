#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
output_dir="${1:-$project_root/build}"
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"
build_temp="$(mktemp -d "${TMPDIR:-/tmp}/lisse-build.XXXXXX")"
trap 'rm -rf "$build_temp"' EXIT
sdk_path="${LISSE_SDK:-}"
if [ -z "$sdk_path" ]; then
  # The newer CLT SDK requires a SwiftUI macro plugin supplied only with Xcode.
  if [ -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]; then
    sdk_path=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
  else
    sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
  fi
fi
for architecture in arm64 x86_64; do
  xcrun swiftc -sdk "$sdk_path" -swift-version 5 -O -whole-module-optimization \
    -module-name Lisse -target "$architecture-apple-macosx13.0" \
    -module-cache-path "$build_temp/cache-$architecture" \
    "$project_root"/Lisse/*.swift -o "$build_temp/Lisse-$architecture"
done
app_path="$output_dir/Lisse.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
lipo -create "$build_temp/Lisse-arm64" "$build_temp/Lisse-x86_64" -output "$app_path/Contents/MacOS/Lisse"
python3 - "$project_root" "$app_path" "$build_temp" <<'PY'
from pathlib import Path
import json, plistlib, re, shutil, sys
root,app,temporary=map(Path,sys.argv[1:])
project=(root/'Lisse.xcodeproj/project.pbxproj').read_text()
version=re.search(r'MARKETING_VERSION = ([^;]+);',project).group(1)
build=re.search(r'CURRENT_PROJECT_VERSION = ([^;]+);',project).group(1)
info=plistlib.loads((root/'Lisse/Info.plist').read_bytes())
info.update(CFBundleExecutable='Lisse',CFBundleIdentifier='com.shrotshahariar.Lisse',CFBundleShortVersionString=version,CFBundleVersion=build,CFBundleSupportedPlatforms=['MacOSX'])
(app/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
(app/'Contents/PkgInfo').write_bytes(b'APPL????')
source=root/'Lisse/Assets.xcassets/AppIcon.appiconset'
iconset=temporary/'AppIcon.iconset'
iconset.mkdir()
for item in json.loads((source/'Contents.json').read_text())['images']:
    suffix='@2x' if item['scale']=='2x' else ''
    shutil.copy2(source/item['filename'],iconset/f"icon_{item['size']}{suffix}.png")
PY
iconutil -c icns "$build_temp/AppIcon.iconset" -o "$app_path/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$app_path"
codesign --verify --deep --strict "$app_path"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$output_dir/Lisse.zip"
printf 'Built %s\n' "$app_path"

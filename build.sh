#!/bin/zsh
set -eu
cd "${0:A:h}"
stage="$(mktemp -d /private/tmp/lightbar-build.XXXXXX)"
app="$stage/LightBar.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$PWD/build/ModuleCache"
xcrun clang -fobjc-arc -arch arm64 -arch x86_64 -fmodules-cache-path="$PWD/build/ModuleCache" -mmacosx-version-min=13.0 -Wall -Wextra -Wno-unused-parameter -framework Cocoa -framework CoreBluetooth -framework ScreenCaptureKit -framework CoreMedia -framework AudioToolbox -framework Accelerate Sources/main.m Sources/AudioCapture.m Sources/Appearance.m Sources/MusicEngine.m -o "$app/Contents/MacOS/LightBar"
cp Resources/Effects.json "$app/Contents/Resources/Effects.json"
xcrun clang -fobjc-arc -framework Cocoa Tools/Icon.m -o "$stage/make-icon"
"$stage/make-icon" "$stage/icon.png"
mkdir -p "$stage/AppIcon.iconset"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$stage/icon.png" --out "$stage/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$stage/icon.png" --out "$stage/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$stage/AppIcon.iconset" -o "$app/Contents/Resources/AppIcon.icns"
cp Resources/Info.plist "$app/Contents/Info.plist"
xattr -cr "$app"
codesign --force --sign - --identifier local.lightbar.controller "$app"
"$app/Contents/MacOS/LightBar" --test
codesign --verify --deep --strict "$app"
ditto --norsrc --noextattr "$app" "$PWD/build/LightBar.app"
ditto -c -k --norsrc --noextattr --keepParent "$app" "$PWD/LightBar.zip"
printf '\nBuilt: %s\n' "$PWD/build/LightBar.app"

#!/bin/zsh
set -eu
cd "${0:A:h}"
stage="$(mktemp -d /private/tmp/lightbar-build.XXXXXX)"
app="$stage/LightBar.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$PWD/build/ModuleCache"
xcrun clang -fobjc-arc -arch arm64 -arch x86_64 -fmodules-cache-path="$PWD/build/ModuleCache" -mmacosx-version-min=13.0 -Wall -Wextra -Wno-unused-parameter -framework Cocoa -framework CoreBluetooth -framework ScreenCaptureKit -framework CoreMedia -framework AudioToolbox Sources/main.m Sources/AudioCapture.m -o "$app/Contents/MacOS/LightBar"
cp Resources/Effects.json "$app/Contents/Resources/Effects.json"
cp Resources/Info.plist "$app/Contents/Info.plist"
xattr -cr "$app"
codesign --force --sign - --identifier local.lightbar.controller "$app"
"$app/Contents/MacOS/LightBar" --test
codesign --verify --deep --strict "$app"
ditto --norsrc --noextattr "$app" "$PWD/build/LightBar.app"
ditto -c -k --norsrc --noextattr --keepParent "$app" "$PWD/LightBar.zip"
printf '\nBuilt: %s\n' "$PWD/build/LightBar.app"

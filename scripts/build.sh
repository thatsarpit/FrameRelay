#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app="build/FrameRelay.app"
if [ -d "$app" ]; then rm -rf "$app"; fi
mkdir -p "$app/Contents/MacOS"
cache="${TMPDIR:-/tmp}/framerelay-swift-cache"
swiftc -target "$(uname -m)-apple-macos14.0" -swift-version 5 -module-cache-path "$cache" -O -framework AppKit -framework SwiftUI -framework Combine -framework CoreMediaIO -framework CoreVideo -framework SystemExtensions -framework ServiceManagement Sources/Shared/*.swift Sources/FrameRelay/*.swift -o "$app/Contents/MacOS/FrameRelay"
mkdir -p "$app/Contents/Resources"
swiftc -module-cache-path "$cache" -framework AppKit scripts/AppIcon.swift -o build/AppIcon
build/AppIcon build/FrameRelay.iconset
iconutil -c icns build/FrameRelay.iconset -o "$app/Contents/Resources/FrameRelay.icns"
cp Resources/Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app"
echo "Built $app (receiver-only, ad-hoc signed)"

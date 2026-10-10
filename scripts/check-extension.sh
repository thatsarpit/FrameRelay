#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
swiftc -target "$(uname -m)-apple-macos14.0" -swift-version 5 -module-cache-path "${TMPDIR:-/tmp}/framerelay-swift-cache" -O -framework CoreMediaIO -framework CoreVideo -framework Security Sources/CameraExtension/main.swift -o build/FrameRelayCameraExtension
printf '%s\n' 'Extension compiled. This does not establish installability or runtime operation.'

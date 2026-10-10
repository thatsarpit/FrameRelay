#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
cache="${TMPDIR:-/tmp}/framerelay-swift-cache"
swiftc -swift-version 5 -module-cache-path "$cache" Sources/Shared/Configuration.swift Tests/ConfigValidationTests.swift -o build/ConfigurationTests
build/ConfigurationTests
swiftc -swift-version 5 -module-cache-path "$cache" -O -framework AppKit -framework Combine -framework CoreVideo Sources/Shared/Configuration.swift Sources/FrameRelay/ReceiverEngine.swift Tests/EngineHarness/main.swift -o build/EngineHarness
python3 Tests/integration.py

#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcodebuild -project Board.xcodeproj -scheme Board -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData test

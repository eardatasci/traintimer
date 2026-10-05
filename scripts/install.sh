#!/bin/sh
# Builds a Release copy of Train Timer, installs it in /Applications and launches it.
set -eu
cd "$(dirname "$0")/.."

xcodebuild -project TrainTimer.xcodeproj -scheme TrainTimer -configuration Release \
    -destination "generic/platform=macOS" -derivedDataPath build/DerivedData build -quiet

pkill -x TrainTimer 2>/dev/null || true
rm -rf /Applications/TrainTimer.app
ditto build/DerivedData/Build/Products/Release/TrainTimer.app /Applications/TrainTimer.app
open /Applications/TrainTimer.app
echo "Installed /Applications/TrainTimer.app"

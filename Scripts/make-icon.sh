#!/bin/bash
# Regenerate the app icon + favicon set from Scripts/make-icon.swift, then
# assemble Resources/AppIcon.icns (iconutil ships with macOS, no Xcode
# needed). Re-run Scripts/bundle-app.sh afterwards to get it into the .app.
set -euo pipefail
cd "$(dirname "$0")/.."

swift Scripts/make-icon.swift
iconutil -c icns build/icon-work/Quoin.iconset -o Resources/AppIcon.icns
echo "Wrote Resources/AppIcon.icns"

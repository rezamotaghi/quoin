#!/bin/bash
# Build the release binary and wrap it into a double-clickable Quoin.app.
# Output: build/Quoin.app (gitignored). Ad-hoc signed: fine for a local
# app; Gatekeeper only interrogates downloaded apps.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP="build/Quoin.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp .build/release/QuoinApp "$APP/Contents/MacOS/Quoin"
# The documented defaults layer; SettingsStore reads it from the bundle.
cp Settings/default-settings.jsonc "$APP/Contents/Resources/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
# Help > Quickstart Guide opens this in the editor.
cp QUICKSTART.md "$APP/Contents/Resources/"
# Color schemes (Phase 3), read by SchemeStore.
mkdir -p "$APP/Contents/Resources/schemes"
cp Settings/schemes/*.jsonc "$APP/Contents/Resources/schemes/"
# Grammar query bundles: SwiftPM emits one <Package>_<Target>.bundle per
# grammar (the highlights.scm files tree-sitter needs at runtime).
cp -R .build/release/TreeSitter*.bundle "$APP/Contents/Resources/"
# Amendment 1: the MCP stdio shim ships inside the app bundle.
# Register with:  claude mcp add quoin -- <app>/Contents/MacOS/QuoinMCP
cp .build/release/QuoinMCP "$APP/Contents/MacOS/QuoinMCP"
codesign --force --sign - "$APP"

echo "Built $APP  (open with: open $APP)"

# Optional: refresh the installed copy so Spotlight and the Dock track the
# latest build. Opt-in by flag; a build script should not write to
# /Applications unasked.
if [[ "${1:-}" == "--install" ]]; then
  ditto "$APP" /Applications/Quoin.app
  echo "Installed /Applications/Quoin.app"
fi

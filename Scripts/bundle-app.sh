#!/bin/bash
# Build the release binary and wrap it into a double-clickable Quoin.app.
# Output: build/Quoin.app (gitignored). Ad-hoc signed: fine for a local
# app; Gatekeeper only interrogates downloaded apps.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
# Ask SwiftPM where the products are; never read the .build/release symlink.
# The Swift Build engine (default from Swift 6.4) writes to
# .build/out/Products/Release and cannot repoint a symlink the native build
# system left behind, so the old path can hold a stale binary and stale
# grammar bundles that copy without complaint.
BIN="$(swift build -c release --show-bin-path)"

APP="build/Quoin.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$BIN/QuoinApp" "$APP/Contents/MacOS/Quoin"
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
cp -R "$BIN"/TreeSitter*.bundle "$APP/Contents/Resources/"
# Amendment 1: the MCP stdio shim ships inside the app bundle.
# Register with:  claude mcp add quoin -- <app>/Contents/MacOS/QuoinMCP
cp "$BIN/QuoinMCP" "$APP/Contents/MacOS/QuoinMCP"
codesign --force --sign - "$APP"

echo "Built $APP  (open with: open $APP)"

# Keep the installed copy current. An existing /Applications/Quoin.app is
# standing consent to keep it updated: a stale installed copy next to a
# fresh repo means two versions of the same bundle id on one machine, and
# that way lie dual instances and misrouted events. First install stays
# opt-in (--install); --no-install skips the refresh.
if [[ "${1:-}" != "--no-install" ]]; then
  if [[ "${1:-}" == "--install" || -d /Applications/Quoin.app ]]; then
    # Replace, never merge: ditto onto an existing bundle keeps every file
    # the new build no longer has, and one stray file breaks the signature's
    # seal (it did, the day the grammar bundles changed shape). Stage beside
    # the target, swap, then check the seal so a bad install cannot pass.
    INSTALLED=/Applications/Quoin.app
    STAGED=/Applications/.Quoin.app.staged
    rm -rf "$STAGED"
    ditto "$APP" "$STAGED"
    rm -rf "$INSTALLED"
    mv "$STAGED" "$INSTALLED"
    codesign --verify --deep --strict "$INSTALLED"
    echo "Installed $INSTALLED"
  fi
fi

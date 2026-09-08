#!/bin/bash
# Build the MCP Bundle (.mcpb) of the QuoinMCP shim for one-click install into
# Claude Desktop: stage the release binary, the manifest, and the license into
# .mcpb/, validate the manifest, pack to dist/quoin-<version>.mcpb. Both folders
# are gitignored; the bundle is attached to the GitHub release by hand. The
# version is read from CITATION.cff (the bump checklist's first line), so the
# manifest in the repo carries a placeholder and never needs its own bump.
# Needs node: the mcpb CLI runs through npx, pinned.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(sed -n 's/^version: *//p' CITATION.cff | tr -d '"')
[[ -n "$VERSION" ]] || { echo "no version in CITATION.cff"; exit 1; }

swift build -c release --product QuoinMCP

rm -rf .mcpb
mkdir -p .mcpb dist
cp .build/release/QuoinMCP .mcpb/QuoinMCP
sed "s/__VERSION__/$VERSION/g" mcpb/manifest.json > .mcpb/manifest.json
cp LICENSE .mcpb/LICENSE

MCPB="npx -y @anthropic-ai/mcpb@2.1.2"
$MCPB validate .mcpb/manifest.json
OUT="dist/quoin-$VERSION.mcpb"
rm -f "$OUT"
$MCPB pack .mcpb "$OUT"
echo "bundle: $OUT"

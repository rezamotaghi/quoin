#!/bin/bash
# The build-and-test gate: swift build && swift test, with the Swift Testing
# macro plugin named. Extra arguments go to swift test (e.g. --filter Name).
#
# Why a wrapper: with Command Line Tools alone (this repo's assumption, no
# Xcode.app) the Swift 6.4 tools of 2026-09 compile a test target without the
# path to libTestingMacros, and every @Test fails with "plugin for module
# 'TestingMacros' not found"; a three-line package shows it, so it is the
# toolchain, not this repo. The plugin sits beside the compiler, in
# usr/lib/swift/host/plugins/testing, so the path is derived from the active
# toolchain and nothing is hardcoded. Where the tools already find it (Xcode,
# older Command Line Tools) the flag only repeats a path they add anyway.
# Build and test get the same flags, or every switch between them would
# recompile the world.
set -euo pipefail
cd "$(dirname "$0")/.."

FLAGS=()
TOOLCHAIN_USR="$(dirname "$(dirname "$(xcrun --find swift)")")"
PLUGINS="$TOOLCHAIN_USR/lib/swift/host/plugins/testing"
if [[ -d "$PLUGINS" ]]; then
  FLAGS=(-Xswiftc -plugin-path -Xswiftc "$PLUGINS")
fi

swift build ${FLAGS[@]+"${FLAGS[@]}"}
swift test ${FLAGS[@]+"${FLAGS[@]}"} "$@"

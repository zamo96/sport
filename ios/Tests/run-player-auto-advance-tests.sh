#!/bin/sh
set -eu

test_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/tennis-player-auto-advance.XXXXXX")
trap 'rm -rf "$temp_dir"' EXIT HUP INT TERM

# Compile the exact production declarations without importing the app's SwiftUI surface.
{
    printf 'import Foundation\nimport CoreGraphics\n'
    sed -n '/^\/\/ MARK: - Player auto-advance state/,/^\/\/ MARK: - End player auto-advance state/p' \
        "$test_dir/../TennisSearchIOS/Views/DiscoverView.swift"
} > "$temp_dir/PlayerAutoAdvanceState.swift"

swiftc "$temp_dir/PlayerAutoAdvanceState.swift" "$test_dir/PlayerAutoAdvanceTests.swift" \
    -o "$temp_dir/player-auto-advance-tests"
"$temp_dir/player-auto-advance-tests"

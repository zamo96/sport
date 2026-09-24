#!/bin/sh
set -eu
test_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/tennis-user-intent.XXXXXX")
trap 'rm -rf "$temp_dir"' EXIT HUP INT TERM
cat > "$temp_dir/LocalizationStub.swift" <<'SWIFT'
enum L10n {
    static func string(_ english: String, _ russian: String) -> String { english }
}
SWIFT
swiftc \
    "$temp_dir/LocalizationStub.swift" \
    "$test_dir/../TennisSearchIOS/Core/UserIntent.swift" \
    "$test_dir/../TennisSearchIOS/Services/UserIntentStore.swift" \
    "$test_dir/UserIntentStoreTests.swift" \
    -o "$temp_dir/user-intent-store-tests"
"$temp_dir/user-intent-store-tests"

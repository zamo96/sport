#!/bin/sh
set -eu
test_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/tennis-sport-home-week.XXXXXX")
trap 'rm -rf "$temp_dir"' EXIT HUP INT TERM

# Exercise the production Foundation projection directly, without UI/network stubs.
swiftc "$test_dir/../TennisSearchIOS/Core/SportHomeWeek.swift" \
    "$test_dir/SportHomeWeekTests.swift" -o "$temp_dir/sport-home-week-tests"
"$temp_dir/sport-home-week-tests"

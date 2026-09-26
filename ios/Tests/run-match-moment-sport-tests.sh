#!/bin/sh
set -eu
test_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/tennis-match-moment-sport.XXXXXX")
trap 'rm -rf "$temp_dir"' EXIT HUP INT TERM

# The production resolver is Foundation-only and generic, so plain strings stand in for Sport.
swiftc "$test_dir/../TennisSearchIOS/Core/MatchMomentSport.swift" \
    "$test_dir/MatchMomentSportTests.swift" -o "$temp_dir/match-moment-sport-tests"
"$temp_dir/match-moment-sport-tests"

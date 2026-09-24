#!/bin/sh
set -eu
test_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/tennis-profile-workouts.XXXXXX")
trap 'rm -rf "$temp_dir"' EXIT HUP INT TERM
swiftc "$test_dir/../TennisSearchIOS/Core/ProfileWorkoutHistory.swift" \
    "$test_dir/../TennisSearchIOS/Core/SportHomeWeek.swift" \
    "$test_dir/ProfileWorkoutHistoryTests.swift" -o "$temp_dir/profile-workout-history-tests"
"$temp_dir/profile-workout-history-tests"

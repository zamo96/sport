#!/bin/sh
set -eu
test_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/tennis-personal-visit-planner.XXXXXX")
trap 'rm -rf "$temp_dir"' EXIT HUP INT TERM

# The planner is Foundation-only: compile the production file as is.
swiftc "$test_dir/../TennisSearchIOS/Core/PersonalVisitPlanner.swift" \
    "$test_dir/PersonalVisitPlannerTests.swift" -o "$temp_dir/personal-visit-planner-tests"
"$temp_dir/personal-visit-planner-tests"

#!/bin/sh
set -eu
test_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/tennis-analytics-ask.XXXXXX")
trap 'rm -rf "$temp_dir"' EXIT HUP INT TERM

# The policy is Foundation-only: compile the production file as is.
swiftc "$test_dir/../TennisSearchIOS/Core/AnalyticsAskPolicy.swift" \
    "$test_dir/AnalyticsAskPolicyTests.swift" -o "$temp_dir/analytics-ask-policy-tests"
"$temp_dir/analytics-ask-policy-tests"

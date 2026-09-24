#!/bin/sh
set -eu
test_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/tennis-secure-session.XXXXXX")
trap 'rm -rf "$temp_dir"' EXIT HUP INT TERM
# Keep all preference cleanup in an isolated suite; exercise the real Security API.
python3 - "$test_dir" "$temp_dir" <<'PY'
from pathlib import Path
import sys
source = (Path(sys.argv[1]).parent / 'TennisSearchIOS/Services/SecureSessionStore.swift').read_text()
source = source.replace('group.shop.sportsearch.app', 'session.tests.' + Path(sys.argv[2]).name)
source = source.replace('SportSearch.sessionToken', 'session.tests.legacy.' + Path(sys.argv[2]).name)
(Path(sys.argv[2]) / 'SecureSessionStore.swift').write_text(source)
PY
swiftc "$temp_dir/SecureSessionStore.swift" "$test_dir/SecureSessionStoreTests.swift" -o "$temp_dir/secure-session-tests"
"$temp_dir/secure-session-tests"

#!/bin/sh
set -eu
test_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/tennis-activity-media.XXXXXX")
trap 'rm -rf "$temp_dir"' EXIT HUP INT TERM
python3 - "$test_dir" "$temp_dir" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1]).parent / 'TennisSearchIOS'
core = (root / 'Core/AppModels.swift').read_text()
api = (root / 'Services/APIClient.swift').read_text()
def declaration(source, name):
    start = source.index(name)
    index = source.index('{', start) + 1
    depth = 1
    while depth:
        depth += (source[index] == '{') - (source[index] == '}')
        index += 1
    return source[start:index]
stubs = '''import Foundation
enum Sport: String, Codable { case tennis }
struct Court: Codable { let name: String }
extension String { func parsedISODateValue() -> Date? { ISO8601DateFormatter().date(from: self) } }
extension Date { func serverISOString() -> String { ISO8601DateFormatter().string(from: self) } }
'''
production = '\n'.join(declaration(core, name) for name in ['struct PersonalActivity:', 'struct PersonalActivityPhoto:', 'struct PersonalActivityUpdateDraft'])
production += '\n' + declaration(api, 'private struct UpdatePersonalActivityRequest:').replace('private struct', 'struct', 1)
(Path(sys.argv[2]) / 'MediaProduction.swift').write_text(stubs + production)
PY
swiftc "$temp_dir/MediaProduction.swift" "$test_dir/PersonalActivityMediaTests.swift" -o "$temp_dir/personal-activity-media-tests"
"$temp_dir/personal-activity-media-tests"

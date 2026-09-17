#!/bin/sh
set -eu

test_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/tennis-player-map.XXXXXX")
trap 'rm -rf "$temp_dir"' EXIT HUP INT TERM

# Actual model decoding and map projection/selection run without UIKit or a server.
# Only unrelated NearbyResult/GameSearch and localization dependencies are stubs.
python3 - "$test_dir" "$temp_dir" <<'PY'
from pathlib import Path
import sys
source_dir = Path(sys.argv[1]).parent / "TennisSearchIOS"
core = (source_dir / "Core/AppModels.swift").read_text()

def declaration(source, name):
    start = source.index(name)
    index = source.index("{", start) + 1
    depth = 1
    while depth:
        depth += (source[index] == "{") - (source[index] == "}")
        index += 1
    return source[start:index]

def section(path, name):
    source = (source_dir / path).read_text()
    start = source.index("// MARK: - " + name + "\n")
    end = source.index("// MARK: - End " + name[0].lower() + name[1:], start)
    return source[start:end]

result = '''import Foundation
import CoreLocation
import MapKit
enum L10n { static func string(_ en: String, _ ru: String) -> String { en } }
struct NearbyResult: Codable {}
struct GameSearch: Codable {}
'''
for name in ["enum Sport:", "enum PlayFormat:", "enum Surface:", "struct DiscoverMapArea:",
             "struct DiscoverUser:", "private extension KeyedDecodingContainer {"]:
    result += "\n" + declaration(core, name)
result += "\n" + section("Views/DiscoverView.swift", "Player map membership projection")
result += "\n" + section("Views/DiscoverPlayersMap.swift", "Player map selection")
result += "\n" + section("Views/DiscoverView.swift", "Schematic player map layout")
(Path(sys.argv[2]) / "PlayerMapProduction.swift").write_text(result)
PY
swiftc "$temp_dir/PlayerMapProduction.swift" "$test_dir/PlayerMapTests.swift" -o "$temp_dir/player-map-tests"
"$temp_dir/player-map-tests"

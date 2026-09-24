#!/bin/sh
set -eu
test_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/tennis-sport-home-load.XXXXXX")
trap 'rm -rf "$temp_dir"' EXIT HUP INT TERM

# Run actual Home loading/session guards with controlled repository responses.
# The harness replaces only SwiftUI state storage and network transport.
python3 - "$test_dir" "$temp_dir" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1]).parent / "TennisSearchIOS"
home = (root / "Views/SportHomeView.swift").read_text()
app = (root / "App/AppModel.swift").read_text()
def declaration(source, name):
    start = source.index(name)
    index = source.index("{", start) + 1
    depth = 1
    while depth:
        depth += (source[index] == "{") - (source[index] == "}")
        index += 1
    return source[start:index]
source = '''import Foundation
struct MatchGameRequest: Equatable { let id: String }
struct PersonalActivity: Equatable { let id: String }
struct User { let id: String }
enum LoadTestError: Error { case unavailable }
@MainActor final class HomeRepository {
    var games: () async throws -> [MatchGameRequest] = { [] }
    var visits: () async throws -> [PersonalActivity] = { [] }
    var gameCalls = 0
    var visitCalls = 0
    func fetchMyGameRequests() async throws -> [MatchGameRequest] { gameCalls += 1; return try await games() }
    func fetchPersonalActivities() async throws -> [PersonalActivity] { visitCalls += 1; return try await visits() }
}
@MainActor final class HomeAppModel {
    let repository = HomeRepository()
    var currentUser: User? = User(id: "A")
    var sessionGeneration = UUID()
'''
source += declaration(app, "    func isCurrentSession(") + "\n}\n"
source += '''@MainActor final class HomeLoadHarness {
    let appModel = HomeAppModel()
    var gameRequests: [MatchGameRequest] = []
    var activities: [PersonalActivity] = []
    var gameLoadFailed = false
    var activityLoadFailed = false
    var isLoading = false
    var hasLoaded = false
    var loadToken = UUID()
    func rebuildProjections() {}
    func invalidateProjections() {}
    func run() async { await load() }
'''
for name in ["    private func load()", "    private func fetchGames()", "    private func fetchVisits()"]:
    source += declaration(home, name) + "\n"
source += "}\n"
(Path(sys.argv[2]) / "HomeLoadProduction.swift").write_text(source)
PY
swiftc "$temp_dir/HomeLoadProduction.swift" "$test_dir/SportHomeLoadTests.swift" \
    -o "$temp_dir/sport-home-load-tests"
"$temp_dir/sport-home-load-tests"

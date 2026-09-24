#!/bin/sh
set -eu
test_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/tennis-profile-workout-loading.XXXXXX")
trap 'rm -rf "$temp_dir"' EXIT HUP INT TERM

# Execute the production profile source loaders with controlled network responses.
# Structural checks ensure private history remains inside the owner's editing view.
python3 - "$test_dir" "$temp_dir" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1]).parent / "TennisSearchIOS"
profile = (root / "Views/ProfileView.swift").read_text()

def declaration(source, name):
    start = source.index(name)
    index = source.index("{", start) + 1
    depth = 1
    while depth:
        depth += (source[index] == "{") - (source[index] == "}")
        index += 1
    return source[start:index]

owner = declaration(profile, "    private var authenticatedContent:")
editing = declaration(owner, "if profileScreenMode == .editing")
assert "ProfileWorkoutsSection(" in editing, "Personal workout history belongs in the owner's editing branch"
assert profile.count("ProfileWorkoutsSection(") == editing.count("ProfileWorkoutsSection(") == 1, "Private history must not also appear in public-preview or guest branches"
assert "ProfileWorkoutsSection(" not in declaration(profile, "    private var guestContent:"), "Guests must not receive private history"
assert "selectedUserIntent" not in editing, "Goal selection must not gate the personal history section"

source = '''import Foundation
struct MatchGameRequest: Equatable { let id: String }
struct PersonalActivity: Equatable { let id: String }
struct ProfileUser { let id: String }
enum L10n { static func string(_ en: String, _ ru: String) -> String { en } }
enum ProfileLoadError: Error { case unavailable }
extension Error { var isCancellationLike: Bool { self is CancellationError } }
@MainActor final class ProfileLoadRepository {
    var games: () async throws -> [MatchGameRequest] = { [] }
    var visits: () async throws -> [PersonalActivity] = { [] }
    var gameCalls = 0
    var visitCalls = 0
    func fetchMyGameRequests() async throws -> [MatchGameRequest] { gameCalls += 1; return try await games() }
    func fetchPersonalActivities() async throws -> [PersonalActivity] { visitCalls += 1; return try await visits() }
}
@MainActor final class ProfileLoadAppModel {
    let repository = ProfileLoadRepository()
    var currentUser: ProfileUser? = ProfileUser(id: "A")
    var isAuthenticated: Bool { currentUser != nil }
}
'''
source += declaration(profile, "private enum ProfileGameFeedSource") + "\n"
source += '''@MainActor final class ProfileWorkoutLoaderHarness {
    let appModel = ProfileLoadAppModel()
    var gameFeedRequests: [MatchGameRequest] = []
    var gameFeedVisits: [PersonalActivity] = []
    var isGameFeedLoading = false
    var isVisitFeedLoading = false
    var gameFeedError: String?
    var visitFeedError: String?
    var gameFeedAccountID: String?
    var gameFeedRequestToken: UUID?
    var visitFeedRequestToken: UUID?
    func run() async { await loadProfileGameFeed() }
    func retryGames() async { await loadProfileGameFeed(source: .games) }
    func retryVisits() async { await loadProfileGameFeed(source: .visits) }
    func oldGames(_ account: String) async { await loadProfileGames(accountID: account) }
    func oldVisits(_ account: String) async { await loadProfileVisits(accountID: account) }
    func reset() { resetProfileGameFeed() }
'''
for name in ["    private func resetProfileGameFeed()", "    private func loadProfileGameFeed(",
             "    private func loadProfileGames(", "    private func loadProfileVisits("]:
    source += declaration(profile, name) + "\n"
source += "}\n"
(Path(sys.argv[2]) / "ProfileWorkoutLoadProduction.swift").write_text(source)
PY
swiftc "$temp_dir/ProfileWorkoutLoadProduction.swift" "$test_dir/ProfileWorkoutLoadingTests.swift" \
    -o "$temp_dir/profile-workout-loading-tests"
"$temp_dir/profile-workout-loading-tests"

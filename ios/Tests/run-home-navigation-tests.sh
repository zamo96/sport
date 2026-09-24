#!/bin/sh
set -eu
test_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/tennis-home-navigation.XXXXXX")
trap 'rm -rf "$temp_dir"' EXIT HUP INT TERM

# Exercise production routing methods with plain state in place of SwiftUI.
# Structural checks cover the entry hierarchy and the removal of goal filtering.
python3 - "$test_dir" "$temp_dir" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1]).parent / "TennisSearchIOS"
content = (root / "Views/ContentView.swift").read_text()
discover = (root / "Views/DiscoverView.swift").read_text()
intent_ui = (root / "Views/UserIntentOnboardingView.swift").read_text()
auth = (root / "Views/AuthView.swift").read_text()
week = (root / "Views/SportHomeView.swift").read_text()
intent_model = (root / "App/AppModel+UserIntent.swift").read_text()

def declaration(source, name):
    start = source.index(name)
    index = source.index("{", start) + 1
    depth = 1
    while depth:
        depth += (source[index] == "{") - (source[index] == "}")
        index += 1
    return source[start:index]

screen = declaration(content, "    private var currentTabScreen:")
assert screen.index("DiscoverView(") < screen.index(".navigationDestination(") < screen.index("SportHomeView("), "Discover must remain the root; the week is an optional destination"
assert "onOpenSportHome:" in screen and '"discover-sport-home-button"' in discover, "The optional week/goal screen must retain its explicit entry"
assert "isForeground: !isSportHomePresented" in screen, "Opening the week must suspend Discover's foreground animation work"
assert "hasNavigatedBeyondEntry = true" in declaration(screen, "onTabChanged:"), "Leaving Players through the visible Discover tabs must not bring back the guide on return"
for obsolete in ["initialGroupsOnly", "groupsOnly", "isGroupSearch"]:
    assert obsolete not in content + discover, "Goal filtering must not hide searches: " + obsolete
assert "selectedUserIntent" not in discover, "Saved goals must not affect Discover's search results"
for name in ["    private func handlePendingNavigation(", "    private func activateTab(", "    private func openHomeIntent(", "    private func openHomeDiscover("]:
    assert "selectedUserIntent" not in declaration(content, name), "Saved goals must not gate existing navigation"
assert "OnboardingMotionHero(" in declaration(auth, "    private var introScreen:"), "The optional goals step must preserve the original onboarding hero"
assert "onContinue([])" in intent_ui, "Skipping goals must save an explicit empty choice"
assert ".disabled(" not in declaration(intent_ui, "    var body:"), "The optional goal screen must not disable Continue when no goals are selected"
assert "featureGuide: featureGuideConfiguration" in screen, "Discover must receive the progress-aware guide configuration"
assert "dismissFeatureGuide" in declaration(content, "    private func openFeatureGuideIntent("), "Choosing a section closes the guide for good, so it opens by itself only once"
assert "selectedUserIntents" not in week and "isIntentPickerPresented" not in week, "The week must not show or filter by goals"
day_action = declaration(week, "    private func weekDayButton(")
assert "selectedWeekDay = day.date" in day_action and "await " not in day_action and "load()" not in day_action, "Day selection must remain local and cannot reload the week"
assert "week.events(on: selectedWeekDay, calendar: calendar)" in declaration(week, "    private var displayedWeekEvents:"), "A selected day must include plans and unresolved events, not only completed workouts"

source = '''import Foundation
enum L10n { static func string(_ en: String, _ ru: String) -> String { en } }
enum MainTab: String { case discover, matches, searches, courts, profile }
enum DiscoverTab: Equatable { case swipe, hot, upcoming, seeking, likes }
enum Sport: Equatable { case tennis, football }
struct Court: Equatable { let id: String }
enum AppNavigationTarget {
    case discover(DiscoverTab, String?, String?, String?)
    case matches, searches, searchLobby(String), createSearch(String), profile, courts(Sport?), chat(String)
}
final class HomeNavigationModel {
    var lastSelectedDiscoverTab: DiscoverTab = .swipe
    var pendingSearchLobbyID: String?
    var pendingCreateSearchPrefill: String?
    var pendingChatMatchID: String?
    var clearCount = 0
    var loadingTabs: Set<String> = []
    var featureGuideProgress = FeatureGuideProgress()
    var selectedUserIntents: Set<UserIntent> = []
    var sessionGeneration = UUID()
    var isOnboardingComplete = true
    var isGuestModeAvailable = false
    var pendingNavigationTarget: AppNavigationTarget?
    var pendingPersonalVisit: String?
    var presentedAuthStep: String?
    func completeFeatureGuideSwipeTutorial() { featureGuideProgress.hasAcknowledgedSwipeTutorial = true }
    func markFeatureGuideOpened(_ intent: UserIntent) { featureGuideProgress.openedIntents.insert(intent) }
    var pendingDiscoverSimilarPlayersHint = false
    // Mirrors AppModel.dismissFeatureGuide: closing queues the swipe tutorial on the Players deck.
    func dismissFeatureGuide() {
        featureGuideProgress.isDismissed = true
        if !featureGuideProgress.hasAcknowledgedSwipeTutorial { lastSelectedDiscoverTab = .swipe; pendingDiscoverSimilarPlayersHint = true }
    }
    func isTabContentLoading(_ tab: String) -> Bool { loadingTabs.contains(tab) }
    func clearPendingNavigation() { clearCount += 1 }
'''
source += declaration(intent_model, "    var shouldShowFeatureGuide:") + "\n}\n"
source += declaration(intent_ui, "struct DiscoverFeatureGuide") + "\n"
source += '''
final class HomeNavigationHarness {
    let appModel = HomeNavigationModel()
    var selectedTab: MainTab = .discover
    var discoverStackID = UUID()
    var matchesStackID = UUID()
    var searchesStackID = UUID()
    var courtsStackID = UUID()
    var profileStackID = UUID()
    var discoverHighlightedUserID: String?
    var discoverHighlightedSearchID: String?
    var discoverHighlightedGameRequestID: String?
    var courtsInitialSport: Sport?
    var courtsVisitPlanningMode = false
    var courtsInitialPersonalVisit: Court?
    var isSportHomePresented = false
    var hasNavigatedBeyondEntry = false
    var discoverViewIdentity = UUID()
    private enum TabActivationSource { case tap }
    func openGoal(_ intent: UserIntent) { openHomeIntent(intent) }
    func openUpcoming(_ gameID: String?) { openHomeDiscover(.upcoming, gameID: gameID) }
    func tap(_ tab: MainTab) { activateTab(tab, source: .tap) }
    func navigate(_ target: AppNavigationTarget?) { handlePendingNavigation(target) }
    var shouldShowLoader: Bool { shouldShowTabLoading }
    var showsFeatureGuide: Bool { shouldShowFeatureGuide }
    var canOpenFeatureGuide: Bool { isFeatureGuideAvailable }
    var guideConfiguration: DiscoverFeatureGuide? { featureGuideConfiguration }
'''
for name in ["    private func handlePendingNavigation(", "    private func activateTab(",
             "    private func openHomeIntent(", "    private func openHomeDiscover(",
             "    private var shouldShowTabLoading:", "    private var isFeatureGuideAvailable:",
             "    private var shouldShowFeatureGuide:", "    private func openFeatureGuideIntent("]:
    source += declaration(content, name) + "\n"
configuration = declaration(content, "    private var featureGuideConfiguration:")
# The production SwiftUI value type uses implicit self. The stateful class harness
# needs explicit captures, with the callback logic otherwise unchanged.
configuration = configuration.replace("onAcknowledgeSwipe: {", "onAcknowledgeSwipe: { [self] in")
configuration = configuration.replace("onOpen: { intent in", "onOpen: { [self] intent in")
configuration = configuration.replace("onDismiss: {", "onDismiss: { [self] in")
source += configuration + "\n"
source += "}\n"
source += "struct FeatureGuideOrderHarness { var selectedIntents: Set<UserIntent>\n"
source += declaration(intent_ui, "    private var orderedIntents:") + "\n"
source += "var actions: [UserIntent] { orderedIntents }\n}\n"
(Path(sys.argv[2]) / "HomeNavigationProduction.swift").write_text(source)
PY
swiftc "$temp_dir/HomeNavigationProduction.swift" "$test_dir/../TennisSearchIOS/Core/UserIntent.swift" \
    "$test_dir/../TennisSearchIOS/Services/UserIntentStore.swift" \
    "$test_dir/HomeNavigationTests.swift" -o "$temp_dir/home-navigation-tests"
"$temp_dir/home-navigation-tests"

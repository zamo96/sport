import Foundation

@main
struct HomeNavigationTests {
    static var checks = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        guard condition() else { fatalError(message) }
    }

    static func main() {
        let navigation = HomeNavigationHarness()
        navigation.isSportHomePresented = true
        navigation.appModel.lastSelectedDiscoverTab = .upcoming
        navigation.discoverHighlightedUserID = "old-user"
        navigation.discoverHighlightedSearchID = "old-search"
        navigation.openGoal(.partner)
        expect(navigation.selectedTab == .discover && navigation.appModel.lastSelectedDiscoverTab == .swipe,
               "The partner action opens the existing Players tab directly")
        expect(!navigation.isSportHomePresented && navigation.discoverHighlightedUserID == nil && navigation.discoverHighlightedSearchID == nil,
               "A goal action dismisses the optional screen and clears stale highlighted entities")
        navigation.isSportHomePresented = true
        navigation.openGoal(.group)
        expect(navigation.selectedTab == .discover && navigation.appModel.lastSelectedDiscoverTab == .hot && !navigation.isSportHomePresented,
               "The company action returns to the existing unfiltered Searches tab")
        navigation.isSportHomePresented = true
        navigation.courtsInitialPersonalVisit = Court(id: "stale-court")
        navigation.courtsInitialSport = .football
        navigation.openGoal(.activity)
        expect(navigation.selectedTab == .courts && navigation.courtsVisitPlanningMode && !navigation.isSportHomePresented,
               "The personal-activity action opens visit planning without a goal gate")
        expect(navigation.courtsInitialSport == nil && navigation.courtsInitialPersonalVisit == nil,
               "A new visit action cannot resurrect a previously deferred court")
        navigation.isSportHomePresented = true
        navigation.openGoal(.centers)
        expect(navigation.selectedTab == .courts && !navigation.courtsVisitPlanningMode && !navigation.isSportHomePresented,
               "The centers action opens the regular catalog rather than the visit composer")

        navigation.isSportHomePresented = true
        navigation.openUpcoming("game-A")
        expect(navigation.selectedTab == .discover && navigation.appModel.lastSelectedDiscoverTab == .upcoming,
               "The week action opens the existing Upcoming tab")
        expect(navigation.discoverHighlightedGameRequestID == "game-A" && !navigation.isSportHomePresented,
               "The exact game context survives leaving the optional week screen")
        navigation.openUpcoming(nil)
        expect(navigation.discoverHighlightedGameRequestID == nil, "Opening all plans clears an earlier game highlight")

        for tab in [DiscoverTab.swipe, .hot, .upcoming] {
            navigation.appModel.lastSelectedDiscoverTab = tab
            navigation.isSportHomePresented = true
            navigation.tap(.discover)
            expect(!navigation.isSportHomePresented && navigation.appModel.lastSelectedDiscoverTab == tab,
                   "Tapping Home returns to the user's current Discover tab, not a goal screen")
        }
        for tab in [MainTab.matches, .searches, .courts, .profile] {
            navigation.isSportHomePresented = true
            navigation.tap(tab)
            expect(navigation.selectedTab == tab && !navigation.isSportHomePresented,
                   "Every bottom-menu tab remains reachable while the optional screen is open")
        }

        navigation.isSportHomePresented = true
        navigation.navigate(.discover(.seeking, "player", "search", "game"))
        expect(navigation.appModel.lastSelectedDiscoverTab == .hot && navigation.selectedTab == .discover && !navigation.isSportHomePresented,
               "A legacy search deep link bypasses the optional screen and resolves to Searches")
        expect(navigation.discoverHighlightedUserID == "player" && navigation.discoverHighlightedSearchID == "search" && navigation.discoverHighlightedGameRequestID == "game",
               "Deep links preserve all entity context")
        expect(navigation.appModel.clearCount == 1, "A routed deep link is consumed exactly once")
        navigation.isSportHomePresented = true
        navigation.navigate(.searchLobby("lobby-A"))
        expect(navigation.selectedTab == .searches && navigation.appModel.pendingSearchLobbyID == "lobby-A" && !navigation.isSportHomePresented,
               "A group-lobby notification bypasses goal selection")
        navigation.isSportHomePresented = true
        navigation.navigate(.chat("match-A"))
        expect(navigation.selectedTab == .matches && navigation.appModel.pendingChatMatchID == "match-A" && !navigation.isSportHomePresented,
               "Chat navigation remains available from the optional week screen")
        navigation.isSportHomePresented = true
        navigation.courtsVisitPlanningMode = true
        navigation.courtsInitialPersonalVisit = Court(id: "stale")
        navigation.navigate(.courts(.tennis))
        expect(navigation.selectedTab == .courts && navigation.courtsInitialSport == .tennis && !navigation.courtsVisitPlanningMode && navigation.courtsInitialPersonalVisit == nil,
               "A center deep link retains its sport and clears unrelated visit continuation UI")
        expect(!navigation.isSportHomePresented, "A center deep link cannot remain behind the optional screen")

        let beforeNil = navigation.appModel.clearCount
        navigation.isSportHomePresented = true
        navigation.navigate(nil)
        expect(navigation.isSportHomePresented && navigation.appModel.clearCount == beforeNil,
               "An absent deep link does not unexpectedly dismiss the user's optional screen")
        navigation.selectedTab = .discover
        navigation.isSportHomePresented = false
        navigation.appModel.loadingTabs = []
        expect(!navigation.shouldShowLoader, "Idle Discover does not show a loading overlay")
        navigation.appModel.loadingTabs = ["discover"]
        expect(navigation.shouldShowLoader, "A real Discover load retains its visible-root loading indicator")
        navigation.isSportHomePresented = true
        expect(!navigation.shouldShowLoader, "Background player loading must never cover the optional sports week")
        navigation.isSportHomePresented = false
        expect(navigation.shouldShowLoader, "Returning to Discover restores an actually pending load indicator")
        navigation.selectedTab = .matches
        navigation.isSportHomePresented = true
        navigation.appModel.loadingTabs = ["matches", "discover"]
        expect(navigation.shouldShowLoader, "Week suppression does not disable loading indicators on other active tabs")
        navigation.appModel.loadingTabs = ["discover"]
        expect(!navigation.shouldShowLoader, "An inactive Discover load does not cover a different bottom-menu tab")

        let guide = HomeNavigationHarness()
        expect(guide.showsFeatureGuide, "An eligible account can see the optional guide at entry")
        guide.appModel.isOnboardingComplete = false
        expect(!guide.showsFeatureGuide, "The feature guide does not bypass required onboarding")
        guide.appModel.isGuestModeAvailable = true
        expect(guide.showsFeatureGuide, "A guest who completed the required draft can see available actions")
        guide.appModel.isGuestModeAvailable = false
        guide.appModel.isOnboardingComplete = true
        guide.appModel.pendingNavigationTarget = .discover(.upcoming, nil, nil, "specific-game")
        expect(!guide.showsFeatureGuide, "An exact game deep link takes precedence over entry suggestions")
        guide.appModel.pendingNavigationTarget = nil
        guide.appModel.pendingPersonalVisit = "specific-court"
        expect(!guide.showsFeatureGuide, "A saved court continuation takes precedence even before it is ready to resume")
        guide.appModel.pendingPersonalVisit = nil
        guide.appModel.presentedAuthStep = "email"
        expect(!guide.showsFeatureGuide, "The guide cannot appear underneath an active authentication sheet")
        guide.appModel.presentedAuthStep = nil
        guide.isSportHomePresented = true
        expect(!guide.showsFeatureGuide, "The sports week does not inherit entry guidance")
        guide.isSportHomePresented = false
        guide.appModel.featureGuideProgress.isDismissed = true
        expect(!guide.showsFeatureGuide, "An account's saved dismissal is respected on a new entry")
        guide.appModel.featureGuideProgress.isDismissed = false
        guide.navigate(nil)
        expect(guide.showsFeatureGuide, "The initial task's absent deep link does not consume the guide")
        guide.navigate(.discover(.upcoming, nil, nil, "specific-game"))
        expect(!guide.showsFeatureGuide && guide.hasNavigatedBeyondEntry,
               "After routing an exact target, clearing it cannot make the guide reappear")
        guide.tap(.discover)
        expect(!guide.showsFeatureGuide, "Returning to the main tab does not reinsert a guide dismissed by session navigation")
        let tabGuide = HomeNavigationHarness()
        tabGuide.tap(.courts)
        expect(!tabGuide.showsFeatureGuide && tabGuide.hasNavigatedBeyondEntry,
               "An explicit bottom-tab choice suspends entry guidance for the session")

        expect(FeatureGuideOrderHarness(selectedIntents: []).actions == UserIntent.allCases,
               "Skipping every goal still exposes all four useful actions")
        expect(FeatureGuideOrderHarness(selectedIntents: [.centers, .group]).actions == [.group, .centers, .partner, .activity],
               "Chosen scenarios come first while every unchosen action remains available")
        expect(FeatureGuideOrderHarness(selectedIntents: Set(UserIntent.allCases)).actions == UserIntent.allCases,
               "Choosing all goals produces four unique actions in a stable order")

        let progress = HomeNavigationHarness()
        let firstGuide = progress.guideConfiguration!
        expect(firstGuide.allowsAutomaticPresentation && !firstGuide.progress.hasAcknowledgedSwipeTutorial,
               "The initial configuration requests the swipe checkpoint before the feature window")
        firstGuide.onAcknowledgeSwipe()
        expect(progress.appModel.featureGuideProgress.hasAcknowledgedSwipeTutorial && progress.appModel.featureGuideProgress.openedIntents.isEmpty,
               "Acknowledging the demonstration does not falsely mark any feature as viewed")
        firstGuide.onOpen(.activity)
        expect(progress.appModel.featureGuideProgress.openedIntents == [.activity] && !progress.appModel.featureGuideProgress.isDismissed,
               "Opening the visit scenario checks only that feature without permanently hiding the guide")
        expect(progress.selectedTab == .courts && progress.courtsVisitPlanningMode && progress.hasNavigatedBeyondEntry,
               "A checked feature still follows the existing real visit-planning route")
        progress.tap(.discover)
        expect(progress.canOpenFeatureGuide && progress.guideConfiguration?.allowsAutomaticPresentation == false,
               "Returning to Players retains manual access without presenting the feature window again automatically")
        let reopened = progress.guideConfiguration!
        expect(reopened.progress.openedIntents == [.activity], "A reopened configuration carries the previous checkmark")
        reopened.onOpen(.group)
        expect(progress.appModel.featureGuideProgress.openedIntents == [.activity, .group] && progress.appModel.lastSelectedDiscoverTab == .hot,
               "The next feature adds its checkmark and opens the unfiltered Searches tab")
        reopened.onDismiss()
        expect(progress.appModel.featureGuideProgress.isDismissed && progress.appModel.featureGuideProgress.openedIntents == [.activity, .group],
               "Closing the window preserves partial progress")
        expect(progress.canOpenFeatureGuide && progress.guideConfiguration?.allowsAutomaticPresentation == false,
               "An explicitly dismissed guide remains manually reopenable")

        let complete = HomeNavigationHarness()
        complete.appModel.featureGuideProgress.openedIntents = Set(UserIntent.allCases)
        expect(!complete.showsFeatureGuide && complete.canOpenFeatureGuide && complete.guideConfiguration != nil,
               "After all four features are viewed the automatic prompt stops, while manual access remains")
        for kind in ["player", "search", "game"] {
            let exact = HomeNavigationHarness()
            if kind == "player" { exact.discoverHighlightedUserID = "exact" }
            if kind == "search" { exact.discoverHighlightedSearchID = "exact" }
            if kind == "game" { exact.discoverHighlightedGameRequestID = "exact" }
            expect(!exact.showsFeatureGuide && !exact.canOpenFeatureGuide && exact.guideConfiguration == nil,
                   "An active highlighted \(kind) destination takes precedence over both automatic and manual guide presentation")
        }

        let oldSession = HomeNavigationHarness()
        let stale = oldSession.guideConfiguration!
        oldSession.appModel.sessionGeneration = UUID()
        stale.onAcknowledgeSwipe()
        stale.onOpen(.centers)
        stale.onDismiss()
        expect(oldSession.appModel.featureGuideProgress == FeatureGuideProgress(),
               "Callbacks retained from an old session cannot acknowledge, check, or dismiss another account's guide")
        expect(oldSession.selectedTab == .discover && !oldSession.hasNavigatedBeyondEntry,
               "An old guide callback cannot redirect the new session")
        print("Home navigation: \(checks) checks passed; root hierarchy and unfiltered-search structure checked")
    }
}

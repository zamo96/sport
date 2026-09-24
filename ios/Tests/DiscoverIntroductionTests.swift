import Foundation
import CoreGraphics

@main
@MainActor
struct DiscoverIntroductionTests {
    static var checks = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        guard condition() else { fatalError(message) }
    }

    static func main() async {
        let fresh = IntroductionHarness()
        fresh.configure()
        fresh.scheduleSimilarPlayersHintIfNeeded()
        let firstID = fresh.introductionTaskID
        fresh.scheduleSimilarPlayersHintIfNeeded()
        expect(fresh.introductionTaskID == firstID, "Repeated load hooks must share one scheduled presentation")
        await fresh.introductionTask?.value
        expect(fresh.introductionPhase == .swipe, "A new user sees swiping before the four possibilities, even with no loaded players")
        expect(!fresh.appModel.featureGuideProgress.hasAcknowledgedSwipeTutorial, "Merely showing the animation cannot acknowledge it")
        expect(fresh.canceledAdvanceCount == 1 && fresh.resetSwipeCount == 1, "The underlying deck stops before showing the tutorial")
        fresh.dismissSimilarPlayersHint()
        fresh.dismissSimilarPlayersHint()
        expect(fresh.appModel.acknowledgedCount == 1, "A rapid double tap acknowledges the tutorial once")
        expect(fresh.introductionPhase == .none && fresh.isIntroductionTransitioning, "The swipe tutorial closes before the next modal opens")
        fresh.scheduleFirstInterestHintIfNeeded()
        expect(!fresh.isFirstInterestHintScheduled, "The legacy interest hint must not overlap the transition")
        await fresh.introductionTask?.value
        expect(fresh.introductionPhase == .opportunities && !fresh.isIntroductionTransitioning, "The four possibilities appear after acknowledgment")
        expect(fresh.appModel.featureGuideProgress.openedIntents.isEmpty, "Viewing the guide does not mark any feature as opened")
        fresh.closeIntroduction()
        expect(fresh.introductionPhase == .none && fresh.appModel.bottomBarDisplayMode == .expanded, "Closing restores the main navigation")

        let resumed = IntroductionHarness()
        resumed.appModel.featureGuideProgress.hasAcknowledgedSwipeTutorial = true
        resumed.appModel.pendingDiscoverSimilarPlayersHint = true
        resumed.configure()
        expect(!resumed.appModel.shouldPresentDiscoverSimilarPlayersHint(), "An old pending flag cannot replay an acknowledged swipe tutorial")
        resumed.scheduleSimilarPlayersHintIfNeeded()
        await resumed.introductionTask?.value
        expect(resumed.introductionPhase == .opportunities && resumed.appModel.consumedSwipeCount == 0, "Returning users resume directly at their feature progress")
        resumed.closeIntroduction()

        let manual = IntroductionHarness()
        manual.appModel.featureGuideProgress = FeatureGuideProgress(hasAcknowledgedSwipeTutorial: true,
            openedIntents: Set(UserIntent.allCases), isDismissed: true)
        manual.configure(automatic: false)
        manual.scheduleSimilarPlayersHintIfNeeded()
        expect(manual.introductionTask == nil, "Dismissed or completed guides cannot open automatically")
        manual.selectedTab = .hot
        manual.similarPlayersDisplayMode = .map
        manual.openIntroductionManually()
        await manual.introductionTask?.value
        expect(manual.selectedTab == .swipe && manual.similarPlayersDisplayMode == .cards && manual.introductionPhase == .opportunities,
               "Manual reopening remains possible after all four checks or explicit dismissal")
        expect(manual.appModel.featureGuideProgress.openedIntents.count == 4 && manual.appModel.featureGuideProgress.isDismissed,
               "Manual presentation does not clear saved familiarity or dismissal")
        manual.closeIntroduction()

        let blockers: [(String, (IntroductionHarness) -> Void)] = [
            ("background source", { $0.isForeground = false }),
            ("invisible source", { $0.isDiscoverVisible = false }),
            ("notifications", { $0.isNotificationsPresented = true }),
            ("inactive scene", { $0.scenePhase = .inactive }),
            ("other tab", { $0.selectedTab = .upcoming }),
            ("map", { $0.similarPlayersDisplayMode = .map }),
            ("initial loading", { $0.isLoading = true }),
            ("refresh", { $0.isSystemRefreshing = true }),
            ("player deep link", { $0.highlightedUserID = "user" }),
            ("search deep link", { $0.highlightedSearchID = "search" }),
            ("game deep link", { $0.highlightedGameRequestID = "game" }),
            ("pending route", { $0.appModel.pendingNavigationTarget = "route" }),
            ("exact visit continuation", { $0.appModel.pendingPersonalVisit = "court" }),
            ("authentication", { $0.appModel.presentedAuthStep = "profile" }),
            ("error", { $0.appModel.errorMessage = "error" }),
            ("busy session", { $0.appModel.isBusy = true }),
            ("visit detail", { $0.selectedPersonalActivityDetails = "visit" }),
            ("report composer", { $0.selectedPersonalActivityReport = "visit" }),
            ("chat", { $0.isUpcomingChatPresented = true }),
            ("search composer", { $0.isHotSearchComposerPresented = true }),
            ("existing hint", { $0.isFirstInterestHintPresented = true }),
            ("swipe submission", { $0.isSubmittingSwipe = true })
        ]
        for (name, block) in blockers {
            let blocked = IntroductionHarness()
            blocked.configure()
            block(blocked)
            blocked.scheduleSimilarPlayersHintIfNeeded()
            expect(blocked.introductionTask == nil && blocked.introductionPhase == .none, "The tutorial must yield to \(name)")
        }

        for (name, interrupt) in [
            ("session replacement", { (h: IntroductionHarness) in h.appModel.sessionGeneration = UUID() }),
            ("owner replacement", { (h: IntroductionHarness) in h.appModel.currentUser = IntroductionUser(id: "B") }),
            ("navigation", { (h: IntroductionHarness) in h.appModel.pendingNavigationTarget = "game" }),
            ("leaving the source", { (h: IntroductionHarness) in h.isForeground = false })
        ] {
            let delayed = IntroductionHarness()
            delayed.configure()
            delayed.scheduleSimilarPlayersHintIfNeeded()
            interrupt(delayed)
            await delayed.introductionTask?.value
            expect(delayed.introductionPhase == .none && !delayed.isSimilarPlayersHintScheduled,
                   "A delayed tutorial must recheck \(name) before presenting")
        }

        let canceled = IntroductionHarness()
        canceled.configure()
        canceled.scheduleSimilarPlayersHintIfNeeded()
        let canceledTask = canceled.introductionTask
        canceled.closeIntroduction()
        canceled.scheduleSimilarPlayersHintIfNeeded()
        let replacementID = canceled.introductionTaskID
        await canceledTask?.value
        expect(canceled.isSimilarPlayersHintScheduled && canceled.introductionTaskID == replacementID,
               "An old canceled task cannot reset the new task's scheduled flag")
        await canceled.introductionTask?.value
        expect(canceled.introductionPhase == .swipe, "The replacement task still presents once")
        canceled.closeIntroduction()

        let transition = IntroductionHarness()
        transition.configure()
        transition.introductionPhase = .swipe
        transition.appModel.bottomBarDisplayMode = .hidden
        transition.dismissSimilarPlayersHint()
        transition.appModel.errorMessage = "interruption"
        await transition.introductionTask?.value
        expect(transition.introductionPhase == .none && !transition.isIntroductionTransitioning,
               "An error between the modals cancels the second presentation")
        expect(transition.appModel.bottomBarDisplayMode == .expanded, "An interrupted transition restores navigation even without another phase change")

        let oldSession = IntroductionHarness()
        oldSession.configure()
        oldSession.introductionPhase = .swipe
        oldSession.dismissSimilarPlayersHint()
        let oldTask = oldSession.introductionTask
        oldSession.appModel.sessionGeneration = UUID()
        oldSession.closeIntroduction() // The production session onChange performs this synchronously.
        oldSession.appModel.bottomBarDisplayMode = .hidden // A modal owned by the new session.
        await oldTask?.value
        expect(oldSession.introductionPhase == .none && oldSession.appModel.bottomBarDisplayMode == .hidden,
               "A canceled old-session transition cannot reopen a guide or change the new session's navigation")

        let reduced = IntroductionHarness()
        reduced.appModel.currentUser = nil
        reduced.reduceMotion = true
        reduced.configure()
        reduced.scheduleSimilarPlayersHintIfNeeded()
        await reduced.introductionTask?.value
        expect(reduced.introductionPhase == .swipe && reduced.introductionAnimation == nil, "Guest entry and Reduce Motion preserve the first step")
        await reduced.runSimilarPlayersHintDemoLoop()
        expect(reduced.similarPlayersHintDemoPhase == 0, "Reduce Motion never starts the looping swipe movement")
        reduced.dismissSimilarPlayersHint()
        await reduced.introductionTask?.value
        expect(reduced.introductionPhase == .opportunities, "Reduce Motion preserves the same explicit progression")
        reduced.closeIntroduction()

        let competing = IntroductionHarness()
        competing.appModel.pendingDiscoverFirstInterestHint = true
        competing.scheduleFirstInterestHintIfNeeded(playerName: "Alice")
        competing.configure()
        competing.scheduleSimilarPlayersHintIfNeeded()
        await competing.introductionTask?.value
        expect(competing.introductionPhase == .swipe && !competing.isFirstInterestHintPresented && competing.appModel.consumedInterestCount == 0,
               "A pre-scheduled interest hint yields to the new tutorial instead of consuming or layering itself")
        competing.closeIntroduction()
        let legacy = IntroductionHarness()
        legacy.appModel.pendingDiscoverSimilarPlayersHint = true
        legacy.scheduleSimilarPlayersHintIfNeeded()
        await legacy.introductionTask?.value
        expect(legacy.introductionPhase == .swipe, "The existing tutorial still works without a feature configuration")
        legacy.dismissSimilarPlayersHint()
        expect(legacy.introductionPhase == .none && !legacy.isIntroductionTransitioning, "The legacy tutorial cannot open a missing guide")

        print("Discover introduction: \(checks) assertions passed")
    }
}

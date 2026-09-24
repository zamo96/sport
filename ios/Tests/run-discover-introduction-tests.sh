#!/bin/sh
set -eu
test_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/tennis-discover-introduction.XXXXXX")
trap 'rm -rf "$temp_dir"' EXIT HUP INT TERM

# Exercise real async presentation methods, guards, and geometry calculations.
# SwiftUI state/animation and application dependencies are replaced by plain state;
# production task delays, cancellation, and session checks remain unchanged.
python3 - "$test_dir" "$temp_dir" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1]).parent / "TennisSearchIOS"
discover = (root / "Views/DiscoverView.swift").read_text()
intent_ui = (root / "Views/UserIntentOnboardingView.swift").read_text()
model = (root / "App/AppModel.swift").read_text()

def declaration(source, name):
    start = source.index(name)
    index = source.index("{", start) + 1
    depth = 1
    while depth:
        depth += (source[index] == "{") - (source[index] == "}")
        index += 1
    return source[start:index]

assert 'Button(L10n.string("Got it", "Хорошо"))' in discover, "Swipe acknowledgment must retain the requested button"
assert 'onOpen: { intent in closeIntroduction(); config.onOpen(intent) }' in discover, "A feature click closes the current modal and routes synchronously"
assert 'onDismiss: { closeFeatureGuide(config) }' in discover, "Closing the feature window must lead into the swipe tutorial"
intent_model = (root / "App/AppModel+UserIntent.swift").read_text()
assert 'queueDiscoverSimilarPlayersHint()' in declaration(intent_model, '    func dismissFeatureGuide()'), "Closing the guide queues the swipe tutorial that follows it"
assert '.onChange(of: appModel.sessionGeneration) { _ in closeIntroduction() }' in discover, "A new session must close the old presentation immediately"
# Cards keep the 2026091904 size and layout: the viewport-fitted compact card hid
# "last seen" on every Players card, because its 500 pt cap always read as compact.
assert 'min(max(UIScreen.main.bounds.height * 0.54, 440), 500)' in discover, "The deck keeps the 2026091904 height"
assert 'availableHeight' not in discover and 'isCompactLayout' not in discover, "Cards must not shrink into the compact layout"
assert 'makeSwipeEmptyResults()' in discover and 'private func makeSwipeEmptyResults()' in discover, "The empty deck must stay outside the large swipe-results getter"

# The physical iOS 18 crash exhausted the main-thread stack while resolving the
# monolithic swipeContent type. These structural guards protect the internal
# type-erasure boundaries; behavioral/device checks remain necessary as well.
swipe_root = declaration(discover, '    private var swipeContent:')
section_names = ['swipeGestureHints', 'swipeResults', 'swipeEmptyResults',
                 'swipeCardDeck', 'swipeDeckGeometryObserver', 'swipeNearbyClubResults']
sections = {name: declaration(discover, '    private var ' + name + ':') for name in section_names}
for name, section in sections.items():
    assert section.split('{', 1)[0].strip().endswith(': AnyView'), name + ' must bound its generic payload before reaching the root tuple'
card = declaration(discover, '    private func swipeDeckCard(')
assert card.split('{', 1)[0].strip().endswith('-> AnyView'), 'Active and background cards need their own metadata boundary'
assert card.count('return AnyView(') == 2, 'Erase both card branches independently instead of aggregating them in a ViewBuilder'
assert 'SwipeCard(' not in swipe_root and 'GeometryReader' not in swipe_root and 'EmptyDeckView(' not in swipe_root, 'Large payloads must not be inlined back into the root VStack'
assert 'AnyView(NearbyResultsBanner(' in swipe_root and 'AnyView(Button(' in swipe_root, 'The other conditional root sections must also keep bounded payloads'
# Measured on the device, the stack went to the body itself: DiscoverView is sized
# at runtime (12.7 KB), each closure capturing self got its own stack copy, and the
# single reader closure held ~54 of them (687 KB) with the tab tree built beneath it.
reader = declaration(discover, '        ScrollViewReader { scrollProxy in')
assert ' '.join(reader.split()) == 'ScrollViewReader { scrollProxy in discoverScreen(scrollProxy) }', 'The reader content must stay one erased call'
screen = declaration(discover, '    private func discoverScreen(')
assert screen.index('discoverScrollContent(scrollProxy)') < screen.index('discoverScroll(content'), 'Build the tab tree before any modifier stage'
for stage in ['discoverScroll', 'discoverLayout', 'discoverNavigation', 'discoverPresentations', 'discoverLifecycle']:
    header = declaration(discover, '    private func ' + stage + '(').split('{', 1)[0]
    assert header.strip().endswith('-> AnyView'), stage + ' must erase its own modifiers so the stages never nest'
assert '.id("similar-players-content")' in swipe_root, 'Preserve the established root identity'
assert 'featureGuideIconDeadline' in discover and 'scheduleFeatureGuideIconHide' in discover, 'The feature guide icon needs a bounded session lifetime'
assert 'discover-search-button' not in discover, 'The toolbar magnifying glass must stay removed while the Searches tab remains'
assert 'visibleActionCount' in intent_ui and 'AppHaptics.impact(.light)' in intent_ui, 'Feature guide actions must reveal progressively with light haptics'
assert all('.id(' not in section for section in [card, *sections.values()]), 'The refactor must not introduce identity resets around cards or branches'
results = sections['swipeResults']
expected_branches = ['if users.isEmpty, !isLoading', 'else if similarPlayersDisplayMode == .grid, !users.isEmpty',
                     'else if visibleSimilarUsers.isEmpty, !isLoading', 'return swipeCardDeck']
assert all(fragment in results for fragment in expected_branches), 'Retain empty, grid, filtered-empty, and deck eligibility'
assert [results.index(fragment) for fragment in expected_branches] == sorted(results.index(fragment) for fragment in expected_branches), 'Preserve the original branch priority'
deck = sections['swipeCardDeck']
assert 'ForEach(Array(topStack.enumerated()), id: \\.element.id)' in deck and 'swipeDeckCard(user: user, index: index)' in deck, 'Card identity must remain the user ID rather than an array position'
assert '.frame(minHeight: swipeDeckMinHeight)' in deck and '.background(swipeDeckGeometryObserver)' in deck, 'The bounded deck must still use its live height budget and geometry observer'
assert 'onMediaCompleted: { completePlayerMedia(userID: user.id) }' in card and 'playbackEnabled: isDeckPlaybackAllowed && autoAdvanceToken == nil' in card, 'Keep completion delivery and active media gating attached to the original user'
assert 'playbackReplayID: autoAdvanceReplayID' in card and 'playbackEnabled: false' in card, 'Retain replay state and disable background media'
assert '.allowsHitTesting(autoAdvanceToken == nil && !isSubmittingSwipe && !isSimilarPlayersHintPresented && !isFirstInterestHintPresented && !isFeatureGuidePresented && !isIntroductionTransitioning)' in card, 'Refactoring cannot enable swipes through a guide or transition'
assert '.simultaneousGesture(dragGesture(for: user))' in card and '.modifier(ViewedCardFlowModifier(flight: viewedCardFlight, progress: viewedFlightProgress))' in card, 'Retain the user-specific gesture and viewed-card flight'
geometry = sections['swipeDeckGeometryObserver']
assert 'updateDeckVisibility(isVisible, requiresVisibility: false)' in geometry, 'Initial visibility must still be measured before first visible playback'
assert '.onChange(of: isVisible) { updateDeckVisibility($0) }' in geometry, 'Only a change of visibility may reach state, not every scrolled frame'
assert '.onDisappear { if isDeckInViewport { isDeckInViewport = false } }' in geometry, 'A disappearing deck must stop counting as visible'
assert '@State private var deckFrame' not in discover, 'Storing the scrolling deck frame re-ran the whole Discover body per frame'
print('Discover metadata boundaries: source guards passed')

source = '''import Foundation
import CoreGraphics
enum L10n { static func string(_ en: String, _ ru: String) -> String { en } }
enum DiscoverTab { case swipe, hot, upcoming }
enum SimilarPlayersDisplayMode { case cards, grid, map }
enum ScenePhase { case active, inactive, background }
enum BottomBarDisplayMode { case expanded, hidden }
enum SwipeAction { case like, dislike }
struct DynamicTypeSize { var isAccessibilitySize = false }
struct Animation {
    static func spring(response: Double, dampingFraction: Double) -> Animation { Animation() }
    static func easeOut(duration: Double) -> Animation { Animation() }
    static func easeInOut(duration: Double) -> Animation { Animation() }
}
func withAnimation(_ animation: Animation?, _ changes: () -> Void) { changes() }
enum AppHaptics { static func selection() {} }
struct IntroductionUser { let id: String }
'''
source += declaration(discover, 'private enum DiscoverIntroductionPhase').replace('private ', '') + '\n'
source += declaration(intent_ui, 'struct DiscoverFeatureGuide') + '\n'
source += '''@MainActor final class IntroductionModel {
    var currentUser: IntroductionUser? = IntroductionUser(id: "A")
    var sessionGeneration = UUID()
    var pendingNavigationTarget: String?
    var pendingPersonalVisit: String?
    var presentedAuthStep: String?
    var errorMessage: String?
    var isBusy = false
    var bottomBarDisplayMode: BottomBarDisplayMode = .expanded
    var pendingDiscoverSimilarPlayersHint = false
    var pendingDiscoverFirstInterestHint = false
    var featureGuideProgress = FeatureGuideProgress()
    var consumedSwipeCount = 0
    var acknowledgedCount = 0
    var consumedInterestCount = 0
    func consumeDiscoverSimilarPlayersHint() { pendingDiscoverSimilarPlayersHint = false; consumedSwipeCount += 1 }
    func completeDiscoverSimilarPlayersHint() { pendingDiscoverSimilarPlayersHint = false }
    func shouldPresentDiscoverFirstInterestHint() -> Bool { pendingDiscoverFirstInterestHint }
    func consumeDiscoverFirstInterestHint() { pendingDiscoverFirstInterestHint = false; consumedInterestCount += 1 }
    // Mirrors AppModel.dismissFeatureGuide (checked above): closing queues the swipe tutorial.
    func dismissFeatureGuide() {
        featureGuideProgress.isDismissed = true
        if !featureGuideProgress.hasAcknowledgedSwipeTutorial { pendingDiscoverSimilarPlayersHint = true }
    }
'''
source += declaration(model, '    func shouldPresentDiscoverSimilarPlayersHint()') + '\n}\n'
source += '''@MainActor final class IntroductionHarness {
    let appModel = IntroductionModel()
    var featureGuide: DiscoverFeatureGuide?
    var introductionPhase: DiscoverIntroductionPhase = .none
    var introductionTask: Task<Void, Never>?
    var introductionTaskID = UUID()
    var isIntroductionTransitioning = false
    var isManualIntroductionRequested = false
    var isSimilarPlayersHintScheduled = false
    var isSimilarPlayersHintDismissing = false
    var isFirstInterestHintPresented = false
    var isFirstInterestHintScheduled = false
    var firstInterestHintPlayerName: String?
    var similarPlayersHintDemoPhase = 0
    var isSubmittingSwipe = false
    var reduceMotion = false
    var isForeground = true
    var isNotificationsPresented = false
    var isDiscoverVisible = true
    var scenePhase: ScenePhase = .active
    var selectedTab: DiscoverTab = .swipe
    var similarPlayersDisplayMode: SimilarPlayersDisplayMode = .cards
    var isLoading = false
    var isSystemRefreshing = false
    var highlightedUserID: String?
    var highlightedSearchID: String?
    var highlightedGameRequestID: String?
    var selectedUpcomingParticipant: String?
    var selectedUpcomingDetailsRequest: String?
    var selectedPersonalActivityDetails: String?
    var selectedPersonalActivityReport: String?
    var selectedPhotoReportRequest: String?
    var selectedUpcomingCourt: String?
    var isUpcomingChatPresented = false
    var presentedRegularPairID: String?
    var presentedSearchLobbyID: String?
    var isHotSearchComposerPresented = false
    var actionCelebration: String?
    var isWidgetHelpPresented = false
    var selectedEditGameRequest: String?
    var selectedShareRequest: String?
    var selectedNextProposalMatch: String?
    var canceledAdvanceCount = 0
    var resetSwipeCount = 0
    var dynamicTypeSize = DynamicTypeSize()
    var deckViewport = CGRect(x: 0, y: 0, width: 390, height: 700)
    var topStack = [0, 1, 2]
    func cancelPlayerAutoAdvance() { canceledAdvanceCount += 1 }
    func resetSwipeInteraction(animated: Bool = true) { resetSwipeCount += 1 }
    func configure(automatic: Bool = true) {
        featureGuide = DiscoverFeatureGuide(selectedIntents: [], progress: appModel.featureGuideProgress,
            allowsAutomaticPresentation: automatic,
            onAcknowledgeSwipe: { [weak self] in
                self?.appModel.acknowledgedCount += 1
                self?.appModel.featureGuideProgress.hasAcknowledgedSwipeTutorial = true
            }, onOpen: { _ in }, onDismiss: { [weak self] in
                // The parent re-renders with the stored dismissal, as MainTabView does.
                self?.appModel.dismissFeatureGuide()
                self?.configure(automatic: false)
            })
    }
'''
for name in [
    '    private var isDiscoverForeground:',
    '    private var isSimilarPlayersHintPresented:', '    private var isFeatureGuidePresented:',
    '    private var hasPendingFeatureIntroduction:', '    private var introductionAnimation:',
    '    private var isIntroductionContextSafe:',
    '    private func scheduleSimilarPlayersHintIfNeeded()', '    private func openIntroductionManually()',
    '    private func closeIntroduction()', '    private func closeFeatureGuide(', '    private func dismissSimilarPlayersHint()',
    '    private func scheduleFirstInterestHintIfNeeded(', '    private func runSimilarPlayersHintDemoLoop()'
]:
    code = declaration(discover, name).replace('    private ', '    ')
    # Value-type SwiftUI captures state implicitly; the class harness needs an
    # explicit capture. No timing, state transitions, or branch logic is changed.
    code = code.replace('Task { @MainActor in', 'Task { @MainActor [self] in')
    source += code + '\n'
source += '}\n'
(Path(sys.argv[2]) / 'DiscoverIntroductionProduction.swift').write_text(source)
PY
swiftc "$temp_dir/DiscoverIntroductionProduction.swift" \
    "$test_dir/../TennisSearchIOS/Core/UserIntent.swift" \
    "$test_dir/../TennisSearchIOS/Services/UserIntentStore.swift" \
    "$test_dir/DiscoverIntroductionTests.swift" -o "$temp_dir/discover-introduction-tests"
"$temp_dir/discover-introduction-tests"

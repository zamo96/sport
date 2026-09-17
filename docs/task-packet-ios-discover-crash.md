# Discover SwiftUI construction crash

## Scope and ownership

User supplied an Xcode screenshot showing EXC_BAD_ACCESS on the main thread in `swift::SubstGenericParametersFromMetadata::buildDescriptorPath`, called through `DiscoverView.tabContentContainer` and body line 480. Fix the crash while preserving the activity feed, similar-player grid and empty-deck changes already in the checkout. Other task owners were idle when ownership was inspected.

Product Analyst defined scope; Solution Architect inspected the type construction and found a large generic switch combining all discovery sections. This is a plausible metadata/depth failure, not yet proof of stack overflow. Mobile owns a narrow change to `selectedTabContent` in DiscoverView.swift. Root owns this packet, baseline capture and native builds/device verification. Independent QA reviews the stable change after checks.

## Design and acceptance

Return AnyView separately from each ordinary switch branch, so SwiftUI does not form an aggregate generic type for all sections. Preserve existing tabContentContainer framing/gesture exclusions and seeking/hot shared identity. Do not add .id or change selection, requests, ranking, gestures or media logic.

- Main discovery screen constructs without crashing.
- Existing upcoming/player/likes/search states, cards/grid, empty/populated and guest/auth presentation remain available.
- Existing gestures and child state are preserved; feed entry and functionality remain unchanged.
- Build native Debug simulator and device binaries; compare startup on the affected connected iPhone when possible.
- Disclose verification gaps and do not claim the exact cause solely from the screenshot.

No domain/API/schema changes: profile, levels, geolocation, availability, match/proposal/lobby lifecycle, ranking, chat, notifications, reliability and premium rules are unchanged. Web/npm/Prisma checks do not apply to this native presentation fix.

## Evidence and results

Baseline source saved outside the repository at `/tmp/tennissearch-discover-crash-before.swift`. Connected device is iPhone 15 on iOS 18.7.8; Xcode currently reports the earlier run finished, so the original paused stack is no longer available. The user screenshot remains the primary crash evidence. Verification results follow below.

- Baseline app reproduced the crash on the connected phone: ordinary launch terminated with signal 11 (`/tmp/tennissearch-discover-crash-baseline.log`).
- Final source change is one hunk: `selectedTabContent` uses ordinary switch returns of `AnyView(upcomingContent/swipeContent/likesContent/searchContent)`. `tabContentContainer`, gestures and all state remain unchanged; no new identity modifier.
- Debug simulator and signed physical-device builds: PASS (`/tmp/tennissearch-discover-crash-simulator-build.log`, `/tmp/tennissearch-discover-crash-device-build.log`). Simulator mock configuration build also PASS for isolated UI regression checks. Scoped whitespace check: PASS.
- Installed the signed Debug app over the existing phone app, with the normal API configuration and no preview arguments. Launch succeeded with PID 6657; later process snapshots confirmed the same process remained running after the baseline crash interval. This verifies startup survival on the affected device, not every possible tab/user-state combination or a definitive runtime-internals diagnosis.
- UI regression setup uses the dedicated Activity Feed simulator, a local mock build and a synthetic guest fixture. No account or preference data on the physical phone was replaced.
- Independent QA: PASS for the minimal fix. Simulator completed two cycles through upcoming-games guest gate, populated searches, incoming-interest guest gate and populated similar players, then Home → activity feed → Home with the same player deck. No crash or real interaction request occurred. Screenshot: `/tmp/tennissearch-discover-crash-home-after.png`.
- Remaining coverage limits: Card/Grid segment buttons were not exposed by the simulator accessibility tree and coordinate clicks failed with `noWindowsAvailable`; signed-in and truly empty fixture combinations were not exercised in the simulator. Existing related code is unchanged by this patch. The physical device process remained alive for more than three minutes after normal launch. The exact Swift runtime failure mechanism is still an inference; the reproduced startup crash and its disappearance after the patch are observed results.

# iOS Discover and activity stability

## Scope

This packet covers the Players screen, the feature guide, My Week, Notifications, and the personal visit media entry point. Backend, ranking, chat, push registration, premium, and sport/profile data contracts are unchanged.

## Acceptance criteria

- Player cards use the restored deck viewport sizing, and the Viewed players strip stays hidden until there is a recorded player to show.
- The four feature guide rows appear in sequence with a short animation and one light haptic per row. Reduce Motion and VoiceOver reveal all rows immediately. Leaving the screen or changing sessions cancels the sequence.
- The feature guide sparkles icon has a subtle pulsing glow, fades after a short lifetime (30 seconds from the first safe Players entry), and stays hidden after that for the same user. An already open guide is not dismissed.
- The toolbar magnifying-glass button is removed; the Searches tab remains available.
- My Week and Notifications do not retain duplicate foreground loads or stale work after leaving and re-entering. Week rendering does not repeatedly rebuild the whole history for each day.
- A completed personal visit exposes an explicit photo/video action. Existing attachments remain when a new report is saved; the existing picker, upload limits, cancellation, and session guards remain in force.

## Domain impact

Direct: iOS Discover layout and navigation, feature-guide presentation, activity history and notification screens, personal visit media UI. No changes to profile, sport/level, location, availability, matching, search lifecycle, chat, push, reliability, or premium.

## Risks and checks

The physical iOS 18 device remains the required check for the prior SwiftUI stack-overflow regression and for navigation responsiveness. Run the targeted Discover, Sport Home, notification lifecycle, personal activity media/report, and home-navigation harnesses, then lint/build and an iOS simulator/device build when available.

#!/bin/sh
set -eu

test_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/tennis-required-onboarding.XXXXXX")
trap 'rm -rf "$temp_dir"' EXIT HUP INT TERM

# Compile actual model declarations and completion methods; only storage/network/UI
# dependencies are replaced so the state transitions run without launching the app.
python3 - "$test_dir" "$temp_dir" <<'PY'
from pathlib import Path
import sys
source_dir = Path(sys.argv[1]).parent / "TennisSearchIOS"
core = (source_dir / "Core/AppModels.swift").read_text()
model = (source_dir / "App/AppModel.swift").read_text()

def declaration(source, name):
    start = source.index(name)
    opening = source.index("{", start)
    depth = 1
    index = opening + 1
    while depth:
        depth += (source[index] == "{") - (source[index] == "}")
        index += 1
    return source[start:index]

names = ["enum SupportedCity:", "enum LocationSource:", "struct LocationCoverage:",
         "struct GeoPlace:", "enum Gender:", "enum Sport:", "enum PlayFormat:",
         "enum Surface:", "enum OnboardingRequirements {", "struct GuestOnboardingDraft:",
         "enum OnboardingMapVisibility {", "struct ConsentState:", "struct UserProfile:", "private extension KeyedDecodingContainer {"]
result = """import Foundation
import CoreLocation

enum L10n { static func string(_ en: String, _ ru: String) -> String { en } }
enum LocaleStore {
    struct EffectiveLocale { let locale = Locale(identifier: "en") }
    static let currentEffectiveLocale = EffectiveLocale()
}
""" + "\n\n".join(declaration(core, name) for name in names)
result += """
@MainActor
final class OnboardingModelHarness {
    var currentUser: UserProfile?
    var guestDraft = GuestOnboardingDraft.default
    var errorMessage: String?
    var draftWrites = 0
    var profileWrites = 0
    var saveSucceeds = true
    func updateGuestDraft(_ draft: GuestOnboardingDraft) { guestDraft = draft; draftWrites += 1 }
    func resetGuestDraft() { guestDraft = .default }
    func saveProfile(_ profile: UserProfile) async -> Bool {
        profileWrites += 1
        if saveSucceeds { currentUser = profile }
        return saveSucceeds
    }
    func restore(_ user: UserProfile) { prepareOnboardingDraft(for: user); currentUser = user }
"""
for name in ["    var isAuthenticated:", "    var isOnboardingComplete:", "    var isGuestModeAvailable:",
             "    func completeGuestOnboarding(", "    private func prepareOnboardingDraft(",
             "    private func makeProfileFromGuestDraft("]:
    result += "\n" + declaration(model, name)
result += "\n}\n"
(Path(sys.argv[2]) / "OnboardingProduction.swift").write_text(result)
PY
swiftc "$temp_dir/OnboardingProduction.swift" "$test_dir/RequiredOnboardingTests.swift" \
    -o "$temp_dir/required-onboarding-tests"
"$temp_dir/required-onboarding-tests"

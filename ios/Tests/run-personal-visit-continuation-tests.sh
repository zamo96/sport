#!/bin/sh
set -eu
test_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/tennis-visit-continuation.XXXXXX")
trap 'rm -rf "$temp_dir"' EXIT HUP INT TERM
python3 - "$test_dir" "$temp_dir" <<'PY'
from pathlib import Path
import sys
source = (Path(sys.argv[1]).parent / 'TennisSearchIOS/App/AppModel.swift').read_text()
def declaration(name):
    start = source.index(name)
    index = source.index('{', start) + 1
    depth = 1
    while depth:
        depth += (source[index] == '{') - (source[index] == '}')
        index += 1
    return source[start:index]
scaffold = '''import Foundation
struct Court: Equatable { let id: String }
enum Sport { case football }
struct TestUser { let id: String; var isOnboardingComplete: Bool }
@MainActor final class PersonalVisitContinuationHarness {
    var currentUser: TestUser?
    var isAuthenticated: Bool { currentUser != nil }
    var isOnboardingComplete: Bool { currentUser?.isOnboardingComplete == true }
    var isBusy = false
    var presentedAuthStep: String?
    var authUserAgreementAccepted = false
    var pendingPersonalVisit: PersonalVisitContinuation?
'''
for name in ['    struct PersonalVisitContinuation {', '    func dismissPresentedAuth()', '    func deferPersonalVisit(', '    func authenticationSheetDidDismiss()', '    var canResumePendingPersonalVisit:', '    func consumePendingPersonalVisit()']:
    scaffold += '\n' + declaration(name)
scaffold += '\n}\n'
(Path(sys.argv[2]) / 'ContinuationProduction.swift').write_text(scaffold)
PY
swiftc "$temp_dir/ContinuationProduction.swift" "$test_dir/PersonalVisitContinuationTests.swift" -o "$temp_dir/personal-visit-continuation-tests"
"$temp_dir/personal-visit-continuation-tests"

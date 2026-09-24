#!/bin/sh
set -eu
test_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/tennis-visit-report-save.XXXXXX")
trap 'rm -rf "$temp_dir"' EXIT HUP INT TERM

# Run the production save orchestration and session guard with controlled transport.
python3 - "$test_dir" "$temp_dir" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1]).parent / "TennisSearchIOS"
composer = (root / "Views/PersonalActivityReportComposerSheet.swift").read_text()
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
enum L10n { static func string(_ en: String, _ ru: String) -> String { en } }
enum PlayerMediaKind { case photo, video }
struct PlayerMediaItem { let kind: PlayerMediaKind; let path: String }
struct PersonalActivity { var id = "visit-A"; var userId = "A"; var status = "planned"; var canComplete = true }
struct PersonalActivityUpdateDraft {
    let scheduledAt: Date?; let durationMinutes: Int?; let comment: String?
    let status: String?; let reportComment: String?; let photoUrls: [String]?; let videoUrls: [String]?
}
struct ReportUser { let id: String }
enum ReportTestError: Error { case unavailable }
extension Error { var isCancellationLike: Bool { self is CancellationError } }
@MainActor final class ReportRepository {
    var photoCalls = 0
    var videoCalls = 0
    var drafts: [PersonalActivityUpdateDraft] = []
    var photos: () async throws -> String = { "/new.jpg" }
    var videos: () async throws -> String = { "/new.mp4" }
    var update: () async throws -> PersonalActivity = { PersonalActivity(status: "completed", canComplete: false) }
    func uploadPersonalActivityPhoto(activityId: String, data: Data, fileName: String, mimeType: String) async throws -> String {
        photoCalls += 1; return try await photos()
    }
    func uploadPersonalActivityVideo(activityId: String, data: Data, fileName: String, mimeType: String) async throws -> String {
        videoCalls += 1; return try await videos()
    }
    func updatePersonalActivity(activityId: String, draft: PersonalActivityUpdateDraft) async throws -> PersonalActivity {
        drafts.append(draft); return try await update()
    }
}
@MainActor final class ReportAppModel {
    var currentUser: ReportUser? = ReportUser(id: "A")
    var sessionGeneration = UUID()
    let repository = ReportRepository()
'''
source += declaration(app, "    func isCurrentSession(") + "\n}\n"
source += declaration(composer, "private struct PendingVisitMedia").replace("private struct", "struct", 1) + "\n"
source += '''@MainActor final class ReportSaveHarness {
    let appModel = ReportAppModel()
    var activity = PersonalActivity()
    var existing: [PlayerMediaItem] = []
    var pending: [PendingVisitMedia] = []
    var generation: UUID?
    var comment = ""
    var isPreparing = false
    var isSubmitting = false
    var errorMessage: String?
    var saved: [PersonalActivity] = []
    var dismissals = 0
    var refreshes = 0
    var onSaved: ((PersonalActivity) -> Void)?
    var count: Int { existing.count + pending.count }
    init() {
        generation = appModel.sessionGeneration
        onSaved = { [weak self] in self?.saved.append($0) }
    }
    func dismiss() { dismissals += 1 }
    func onSubmitted() async { refreshes += 1 }
    func run() async { await save() }
'''
source += declaration(composer, "    private var commentLength:") + "\n"
source += declaration(composer, "    @MainActor private func save()") + "\n}\n"
(Path(sys.argv[2]) / "ReportSaveProduction.swift").write_text(source)
PY
swiftc "$temp_dir/ReportSaveProduction.swift" "$test_dir/PersonalActivityReportSaveTests.swift" \
    -o "$temp_dir/personal-activity-report-save-tests"
"$temp_dir/personal-activity-report-save-tests"

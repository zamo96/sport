import Foundation

@main
@MainActor
struct PersonalActivityReportSaveTests {
    static var checks = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        guard condition() else { fatalError(message) }
    }
    static func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<10_000 {
            if condition() { return }
            await Task.yield()
        }
        fatalError("Controlled report request did not start")
    }

    static func main() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("visit-save-tests-\(UUID().uuidString)")
        try Data([1, 2, 3]).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        func pending(_ kind: PlayerMediaKind) -> PendingVisitMedia {
            .init(id: UUID(), kind: kind, url: file, mimeType: kind == .photo ? "image/jpeg" : "video/mp4", uploadedURL: nil)
        }

        let empty = ReportSaveHarness()
        empty.comment = "Felt good"
        await empty.run()
        let emptyDraft = empty.appModel.repository.drafts.first!
        expect(emptyDraft.status == "completed" && emptyDraft.reportComment == "Felt good" && emptyDraft.photoUrls == [] && emptyDraft.videoUrls == [],
               "A visit can be explicitly completed with a note and no media")
        expect(empty.appModel.repository.photoCalls == 0 && empty.appModel.repository.videoCalls == 0,
               "A no-media result makes no upload request")
        expect(empty.saved.count == 1 && empty.dismissals == 1 && empty.refreshes == 1 && !empty.isSubmitting,
               "A successful save refreshes once, dismisses once, and settles submission state")
        let trimmed = ReportSaveHarness()
        trimmed.comment = "  " + String(repeating: "🎾", count: 120) + "\n"
        await trimmed.run()
        expect(trimmed.appModel.repository.drafts.count == 1,
               "Exactly 240 UTF-16 units plus trim whitespace remain valid as on the server")

        let preserve = ReportSaveHarness()
        preserve.activity.status = "completed"
        preserve.activity.canComplete = false
        preserve.existing = [.init(kind: .photo, path: "/old.jpg"), .init(kind: .video, path: "/old.mov")]
        preserve.pending = [pending(.video), pending(.photo)]
        await preserve.run()
        expect(preserve.appModel.repository.drafts.first?.photoUrls == ["/old.jpg", "/new.jpg"] && preserve.appModel.repository.drafts.first?.videoUrls == ["/old.mov", "/new.mp4"],
               "Adding mixed media preserves existing attachments and each media kind's order")
        expect(preserve.appModel.repository.photoCalls == 1 && preserve.appModel.repository.videoCalls == 1,
               "Only newly selected attachments upload when editing a completed visit")

        let partial = ReportSaveHarness()
        partial.existing = [.init(kind: .photo, path: "/kept.jpg")]
        partial.pending = [pending(.photo), pending(.video)]
        partial.appModel.repository.videos = { throw ReportTestError.unavailable }
        await partial.run()
        expect(partial.appModel.repository.drafts.isEmpty && partial.saved.isEmpty && partial.dismissals == 0,
               "A failed attachment upload cannot patch completion, announce success, or close the editor")
        expect(partial.existing.map(\.path) == ["/kept.jpg"] && partial.pending.first?.uploadedURL == "/new.jpg" && partial.pending.last?.uploadedURL == nil,
               "Upload failure preserves previous attachments and reusable successful uploads")
        expect(partial.errorMessage != nil && !partial.isSubmitting, "Upload failure is visible and leaves the editor ready to retry")
        partial.appModel.repository.videos = { "/retry.mp4" }
        await partial.run()
        expect(partial.appModel.repository.photoCalls == 1 && partial.appModel.repository.videoCalls == 2 && partial.appModel.repository.drafts.count == 1,
               "Retry uploads only the failed attachment before one completion request")
        expect(partial.appModel.repository.drafts.first?.photoUrls == ["/kept.jpg", "/new.jpg"] && partial.appModel.repository.drafts.first?.videoUrls == ["/retry.mp4"],
               "The retry commits the full preserved report without duplicate media")

        let patchFailure = ReportSaveHarness()
        patchFailure.pending = [pending(.video)]
        patchFailure.appModel.repository.update = { throw ReportTestError.unavailable }
        await patchFailure.run()
        expect(patchFailure.saved.isEmpty && patchFailure.dismissals == 0 && patchFailure.pending.first?.uploadedURL == "/new.mp4",
               "A failed final patch keeps the draft and uploaded media available for retry")
        patchFailure.appModel.repository.update = { PersonalActivity(status: "completed", canComplete: false) }
        await patchFailure.run()
        expect(patchFailure.appModel.repository.videoCalls == 1 && patchFailure.saved.count == 1,
               "Retrying the final patch does not upload an already saved file again")

        for invalid in ["foreign", "future", "canceled", "preparing", "long-note", "unicode-note", "too-many"] {
            let draft = ReportSaveHarness()
            draft.pending = [pending(.photo)]
            switch invalid {
            case "foreign": draft.activity.userId = "B"
            case "future": draft.activity.canComplete = false
            case "canceled": draft.activity.status = "canceled"; draft.activity.canComplete = false
            case "preparing": draft.isPreparing = true
            case "long-note": draft.comment = String(repeating: "a", count: 241)
            case "unicode-note": draft.comment = String(repeating: "🎾", count: 121)
            default: draft.existing = (0..<8).map { .init(kind: .photo, path: "/\($0).jpg") }
            }
            await draft.run()
            expect(draft.appModel.repository.photoCalls == 0 && draft.appModel.repository.drafts.isEmpty,
                   "Invalid \(invalid) state is rejected before uploads or mutations")
        }

        let overlap = ReportSaveHarness()
        overlap.pending = [pending(.photo)]
        var upload: CheckedContinuation<String, Error>?
        overlap.appModel.repository.photos = { try await withCheckedThrowingContinuation { upload = $0 } }
        let saving = Task { await overlap.run() }
        await waitUntil { upload != nil }
        await overlap.run()
        expect(overlap.appModel.repository.photoCalls == 1 && overlap.appModel.repository.drafts.isEmpty,
               "A second Save during an upload cannot create duplicate requests")
        upload!.resume(returning: "/once.jpg")
        await saving.value
        expect(overlap.appModel.repository.drafts.count == 1 && overlap.saved.count == 1,
               "The original in-flight save finishes exactly once")

        let switched = ReportSaveHarness()
        switched.pending = [pending(.photo), pending(.video)]
        var switchedUpload: CheckedContinuation<String, Error>?
        switched.appModel.repository.photos = { try await withCheckedThrowingContinuation { switchedUpload = $0 } }
        let oldAccountSave = Task { await switched.run() }
        await waitUntil { switchedUpload != nil }
        switched.appModel.currentUser = ReportUser(id: "B")
        switched.appModel.sessionGeneration = UUID()
        switchedUpload!.resume(returning: "/old-account.jpg")
        await oldAccountSave.value
        expect(switched.appModel.repository.videoCalls == 0 && switched.appModel.repository.drafts.isEmpty && switched.saved.isEmpty && switched.refreshes == 0,
               "Changing accounts during upload suppresses subsequent uploads, mutations, and callbacks")
        expect(switched.pending.first?.uploadedURL == nil && switched.errorMessage == nil,
               "Old-account upload results cannot modify the next account's editor state")

        let canceled = ReportSaveHarness()
        canceled.pending = [pending(.video)]
        var canceledUpload: CheckedContinuation<String, Error>?
        canceled.appModel.repository.videos = { try await withCheckedThrowingContinuation { canceledUpload = $0 } }
        let canceledSave = Task { await canceled.run() }
        await waitUntil { canceledUpload != nil }
        canceledSave.cancel()
        canceledUpload!.resume(returning: "/canceled.mp4")
        await canceledSave.value
        expect(canceled.appModel.repository.drafts.isEmpty && canceled.saved.isEmpty && canceled.errorMessage == nil,
               "Task cancellation rejects a transport result even when the upload ignores cancellation")

        let patchSwitch = ReportSaveHarness()
        var patch: CheckedContinuation<PersonalActivity, Error>?
        patchSwitch.appModel.repository.update = { try await withCheckedThrowingContinuation { patch = $0 } }
        let oldPatch = Task { await patchSwitch.run() }
        await waitUntil { patch != nil }
        patchSwitch.appModel.currentUser = nil
        patchSwitch.appModel.sessionGeneration = UUID()
        patch!.resume(returning: PersonalActivity(status: "completed", canComplete: false))
        await oldPatch.value
        expect(patchSwitch.saved.isEmpty && patchSwitch.dismissals == 0 && patchSwitch.refreshes == 0,
               "A patch response after logout cannot update or dismiss the current screen")
        print("Personal activity report save: \(checks) checks passed")
    }
}

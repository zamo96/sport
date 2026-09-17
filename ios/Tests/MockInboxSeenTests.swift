import Foundation

@main
struct MockInboxSeenTests {
    static var assertions = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        guard condition() else { fatalError(message) }
    }

    static func message(_ id: String, sender: String = "other", game: String? = nil) -> ChatMessage {
        ChatMessage(
            id: id, senderUserId: sender, gameRequestId: game, text: "Hello",
            createdAt: "2026-09-17T12:00:00Z", senderUser: nil,
            receipt: ChatReceipt(status: "delivered", deliveredCount: 1, readCount: 0)
        )
    }

    static func main() async throws {
        let repository = MockInboxHarness()
        expect(repository.inboxBadgeCount == 0, "Empty inbox has no badge")
        repository.matches = [InboxMatch(id: "m1"), InboxMatch(id: "m2"), InboxMatch(id: "archived", status: "archived")]
        repository.messagesByMatch = [
            "m1": [message("a"), message("b"), message("c", game: "g1"), message("d", game: "g1"), message("own", sender: "self", game: "own-game")],
            "archived": [message("archived-message")],
            "orphan": [message("orphan-message")]
        ]
        expect(repository.inboxBadgeCount == 3, "Distinct active match/game scopes count once; inactive, orphan, and own messages do not add scopes")

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let receiptsAndMessagesBefore = try encoder.encode(repository.messagesByMatch)
        try await repository.markInboxSeen()
        expect(repository.inboxBadgeCount == 0, "Opening inbox clears the badge")
        let receiptsAndMessagesAfter = try encoder.encode(repository.messagesByMatch)
        expect(receiptsAndMessagesBefore == receiptsAndMessagesAfter, "Opening inbox does not mutate message content or chat delivery/read receipts")
        for _ in 0..<5 {
            expect(repository.inboxBadgeCount == 0, "Repeated activity refresh cannot restore seen events")
        }
        try await repository.markInboxSeen()
        expect(repository.inboxBadgeCount == 0, "Repeated mark-seen is idempotent")

        repository.messagesByMatch["m1", default: []].append(message("new-a"))
        expect(repository.inboxBadgeCount == 1, "A new incoming message in an old match restores its badge")
        repository.messagesByMatch["m1", default: []].append(message("new-b"))
        expect(repository.inboxBadgeCount == 1, "Multiple new messages in one match count once")
        repository.messagesByMatch["m2", default: []].append(message("new-own", sender: "self"))
        expect(repository.inboxBadgeCount == 1, "Own messages do not restore a seen match badge")
        repository.messagesByMatch["m1", default: []].append(message("new-game", game: "g2"))
        expect(repository.inboxBadgeCount == 2, "A new game thread uses its gameRequestId identity")
        repository.matches.append(InboxMatch(id: "m3"))
        expect(repository.inboxBadgeCount == 3, "A new match counts even without messages")
        repository.messagesByMatch["archived", default: []].append(message("new-archived"))
        expect(repository.inboxBadgeCount == 3, "New messages in inactive matches stay excluded")
        try await repository.markInboxSeen()
        repository.matches[2].status = "active"
        expect(repository.inboxBadgeCount == 0, "Activating previously seen old data does not invent a new event")
        repository.messagesByMatch["archived", default: []].append(message("after-reactivation"))
        expect(repository.inboxBadgeCount == 1, "A fresh incoming message after reactivation is counted")

        try await repository.deleteAccount()
        expect(repository.inboxBadgeCount == 0, "Account deletion clears the inbox")
        expect(repository.seenInboxMatchIDs.isEmpty && repository.seenInboxIncomingMessageIDs.isEmpty, "Account deletion clears mock seen snapshots")
        repository.matches = [InboxMatch(id: "m1")]
        repository.messagesByMatch = ["m1": [message("a")]]
        expect(repository.inboxBadgeCount == 1, "A new mock account is not suppressed by old seen identities")
        print("PASS: \(assertions) mock inbox seen assertions")
    }
}

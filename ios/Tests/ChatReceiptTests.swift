import Foundation

@main
struct ChatReceiptTests {
    static var assertions = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        guard condition() else { fatalError(message) }
    }

    static func main() throws {
        var state = ChatReceiptAcknowledgementState()
        state.incomingIDs = ["first", "offscreen"]
        state.visibleIDs = ["first", "outgoing", "not-fetched"]
        expect(state.pendingIDs(status: "delivered") == ["first", "offscreen"], "Delivery only acknowledges fetched incoming IDs")
        expect(state.pendingIDs(status: "read").isEmpty, "Background/covered chat cannot acknowledge read")
        state.isActive = true
        expect(state.pendingIDs(status: "read") == ["first"], "Only visible incoming rows are read, never offscreen or outgoing rows")
        // Failed requests don't call confirm and remain eligible for retry.
        expect(state.pendingIDs(status: "read") == ["first"], "An unconfirmed read remains pending")
        state.confirm(["first"], status: "read")
        expect(state.pendingIDs(status: "read").isEmpty, "Repeated callbacks do not duplicate confirmed reads")
        expect(state.pendingIDs(status: "delivered") == ["offscreen"], "Read implies delivered")
        state.confirm(["first"], status: "delivered")
        expect(state.readIDs.contains("first"), "Late delivery acknowledgement does not regress read")
        state.incomingIDs.insert("new")
        expect(state.pendingIDs(status: "read").isEmpty, "Newly fetched messages need actual viewport evidence")
        state.visibleIDs.insert("new")
        expect(state.pendingIDs(status: "read") == ["new"], "Visible new rows become readable")
        state.isActive = false
        expect(state.pendingIDs(status: "read").isEmpty, "Losing foreground invalidates pending visibility")
        state.incomingIDs = Set((0..<451).map { "message-\($0)" })
        let firstBatch = state.pendingIDs(status: "delivered")
        expect(firstBatch.count == 200, "Large histories respect endpoint batch limit")
        state.confirm(firstBatch, status: "delivered")
        let secondBatch = state.pendingIDs(status: "delivered")
        expect(secondBatch.count == 200 && Set(firstBatch).isDisjoint(with: secondBatch), "Batches advance without losing messages")
        state.confirm(secondBatch, status: "delivered")
        expect(state.pendingIDs(status: "delivered").count == 51, "Final partial batch preserves every fetched message")

        let viewport = CGRect(x: 0, y: 100, width: 300, height: 400)
        expect(ChatReceiptAcknowledgementState.isVisible(row: CGRect(x: 0, y: 150, width: 200, height: 80), viewport: viewport), "Visible row is eligible")
        expect(!ChatReceiptAcknowledgementState.isVisible(row: CGRect(x: 0, y: 510, width: 200, height: 80), viewport: viewport), "Laid-out offscreen VStack row is not read")
        expect(!ChatReceiptAcknowledgementState.isVisible(row: CGRect(x: 0, y: 490, width: 200, height: 80), viewport: viewport), "Tiny exposed edge is insufficient")
        expect(ChatReceiptAcknowledgementState.isVisible(row: CGRect(x: 0, y: 460, width: 200, height: 80), viewport: viewport), "Half-visible row is eligible")
        expect(ChatReceiptAcknowledgementState.isVisible(row: CGRect(x: 0, y: 50, width: 200, height: 1200), viewport: viewport), "Long message can be read within smaller viewport")
        expect(!ChatReceiptAcknowledgementState.isVisible(row: .zero, viewport: viewport), "Unmeasured row is not read")
        expect(!ChatReceiptAcknowledgementState.isVisible(row: viewport, viewport: .zero), "Unmeasured viewport is not read")

        let legacy = Data(#"{"id":"m1","senderUserId":"sender","createdAt":"2026-09-08T10:00:00Z"}"#.utf8)
        let direct = try JSONDecoder().decode(ChatMessage.self, from: legacy)
        let lobby = try JSONDecoder().decode(SearchLobbyMessage.self, from: legacy)
        expect(direct.receipt == nil && direct.attachments.isEmpty, "Legacy direct payload remains decodable")
        expect(lobby.receipt == nil && lobby.attachments.isEmpty, "Legacy lobby payload remains decodable")
        let current = Data(#"{"id":"m1","senderUserId":"sender","createdAt":"2026-09-08T10:00:00Z","receipt":{"status":"read","deliveredCount":3,"readCount":2}}"#.utf8)
        let updatedDirect = try JSONDecoder().decode(ChatMessage.self, from: current)
        let updatedLobby = try JSONDecoder().decode(SearchLobbyMessage.self, from: current)
        expect(updatedDirect.receipt?.status == "read" && updatedDirect.id == direct.id, "Receipt-only updates retain identity and decode new status")
        expect(updatedLobby.receipt?.readCount == 2 && updatedLobby.receipt?.deliveredCount == 3, "Group recipient counts decode intact")
        let mergedDirect = mergeChatReceipts(current: [updatedDirect], fetched: [direct])
        expect(mergedDirect.first?.receipt?.status == "read", "Older response without receipts cannot regress a confirmed read")
        let partial = ChatReceipt(status: "delivered", deliveredCount: 1, readCount: 0)
        let mergedCounts = ChatReceipt.merged(updatedLobby.receipt, partial)
        expect(mergedCounts?.status == "read" && mergedCounts?.deliveredCount == 3 && mergedCounts?.readCount == 2, "Out-of-order group receipts preserve counts and read state")
        let another = ChatMessage(id: "other", senderUserId: "sender", text: "", createdAt: "now", senderUser: nil)
        expect(mergeChatReceipts(current: [updatedDirect], fetched: [another]).first?.receipt == nil, "Receipt merge never leaks to a different message")
        expect(mergeChatReceipts(current: [updatedDirect], fetched: [ChatMessage]()).isEmpty, "Authorized history removals are not resurrected by receipt merging")
        let advanced = ChatReceipt.merged(partial, updatedDirect.receipt)
        expect(advanced?.status == "read", "Later read advances previous delivery")
        print("PASS: \(assertions) chat receipt assertions")
    }
}

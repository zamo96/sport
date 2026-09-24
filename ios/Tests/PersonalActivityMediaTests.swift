import Foundation

@main
struct PersonalActivityMediaTests {
    static var checks = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        guard condition() else { fatalError(message) }
    }
    static func main() throws {
        var json: [String: Any] = ["id": "a", "userId": "owner", "courtId": "c", "sport": "tennis",
                                  "scheduledAt": "2020-01-01T12:00:00Z", "status": "completed",
                                  "photos": [["id": "p", "url": "/photo.jpg", "position": 0]]]
        func decode() throws -> PersonalActivity {
            try JSONDecoder().decode(PersonalActivity.self, from: JSONSerialization.data(withJSONObject: json))
        }
        let legacy = try decode()
        expect(legacy.videoUrls.isEmpty && legacy.photoUrls == ["/photo.jpg"], "Photo-only old responses retain photos and decode videos as empty")
        json["videoUrls"] = ["/one.mp4", "/two.mov"]
        let mixed = try decode()
        expect(mixed.videoUrls == ["/one.mp4", "/two.mov"], "New video order decodes without affecting photo order")
        let roundTrip = try JSONDecoder().decode(PersonalActivity.self, from: JSONEncoder().encode(mixed))
        expect(roundTrip.videoUrls == mixed.videoUrls && roundTrip.photoUrls == mixed.photoUrls, "Mixed media survives Codable round trip")
        json["videoUrls"] = NSNull()
        let nullable = try decode()
        expect(nullable.videoUrls.isEmpty, "Nullable legacy-compatible payload decodes empty videos")
        let noMedia = PersonalActivity(id: "b", userId: "owner", courtId: "c", sport: .tennis,
            scheduledAt: "2020-01-01T12:00:00Z", durationMinutes: nil, comment: nil, status: "completed",
            reportComment: nil, createdAt: nil, updatedAt: nil, court: nil, photos: [])
        expect(noMedia.videoUrls.isEmpty, "Existing memberwise construction is source compatible")
        var draft = PersonalActivityUpdateDraft(reportComment: "Changed note")
        func payload() throws -> [String: Any] {
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(UpdatePersonalActivityRequest(draft: draft))) as! [String: Any]
        }
        var encoded = try payload()
        expect(encoded["videoUrls"] == nil && encoded["photoUrls"] == nil, "Notes-only save omits both media lists")
        draft.videoUrls = []; encoded = try payload()
        expect((encoded["videoUrls"] as? [String]) == [] && encoded["photoUrls"] == nil, "An explicit empty video list clears only videos")
        draft.photoUrls = ["/photo.jpg"]; draft.videoUrls = ["/one.mp4"]; encoded = try payload()
        expect((encoded["videoUrls"] as? [String]) == ["/one.mp4"] && (encoded["photoUrls"] as? [String]) == ["/photo.jpg"], "Both attachment lists are sent when intentionally updated")
        expect(legacy.hasEnded && !legacy.canComplete, "Completed records remain completed instead of offering duplicate completion")
        print("Personal activity media: \(checks) checks passed")
    }
}

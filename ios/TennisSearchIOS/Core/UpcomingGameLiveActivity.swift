import ActivityKit
import Foundation

struct UpcomingGameLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var sportTitle: String
        var courtName: String
        var courtAddress: String?
        var statusLabel: String
        var startsAt: Date
        var durationMinutes: Int
        var updatedAt: Date

        var endsAt: Date {
            startsAt.addingTimeInterval(TimeInterval(durationMinutes * 60))
        }
    }

    let gameId: String
}

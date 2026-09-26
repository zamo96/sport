import Foundation

/// Which sport a new match is about, so its moment plays that sport rather than tennis.
enum MatchMomentSportResolver {
    /// The deck's sport filter wins: it is what the viewer was browsing for. Otherwise the
    /// first sport both players list, in the viewer's own order; then the other player's
    /// main sport, since theirs is the card that was liked; then the viewer's; the fallback
    /// only when neither profile names a sport.
    static func resolve<Sport: Equatable>(deckFilter: Sport?, viewer: [Sport], player: [Sport], fallback: Sport) -> Sport {
        if let deckFilter {
            return deckFilter
        }
        if let shared = viewer.first(where: { player.contains($0) }) {
            return shared
        }
        return player.first ?? viewer.first ?? fallback
    }
}

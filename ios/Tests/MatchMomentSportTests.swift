import Foundation

@main
struct MatchMomentSportTests {
    static var checks = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        guard condition() else { fatalError(message) }
    }

    static func resolve(filter: String? = nil, viewer: [String], player: [String]) -> String {
        MatchMomentSportResolver.resolve(deckFilter: filter, viewer: viewer, player: player, fallback: "tennis")
    }

    static func main() {
        expect(resolve(filter: "padel", viewer: ["tennis"], player: ["tennis", "padel"]) == "padel",
               "The deck's sport filter is what the viewer was browsing for, even over a shared first sport")
        expect(resolve(viewer: ["football", "tennis", "padel"], player: ["padel", "tennis"]) == "tennis",
               "Among shared sports the viewer's own order decides")
        expect(resolve(viewer: ["running"], player: ["badminton", "yoga"]) == "badminton",
               "With nothing shared, the liked player's main sport is the one on the card")
        expect(resolve(viewer: ["yoga"], player: []) == "yoga",
               "A player without sports falls back to the viewer's")
        expect(resolve(viewer: [], player: []) == "tennis",
               "Only two empty profiles reach the fallback")

        print("Match moment sport: \(checks) checks passed")
    }
}

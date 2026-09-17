import Foundation
import CoreGraphics

@main
struct PlayerAutoAdvanceTests {
    static var assertions = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        guard condition() else { fatalError(message) }
    }

    static func expectNear(_ actual: CGFloat, _ expected: CGFloat, _ message: String) {
        expect(actual.isFinite && abs(actual - expected) < 0.00001, message)
    }

    static func testViewedFlightGeometry() {
        let cases: [(CGRect, CGRect)] = [
            (CGRect(x: 16, y: 210, width: 358, height: 500), CGRect(x: 30, y: 720, width: 46, height: 46)),
            (CGRect(x: -120, y: -30, width: 390, height: 440), CGRect(x: 300, y: 660, width: 46, height: 46)),
            (CGRect(x: 220, y: 380, width: 700, height: 600), CGRect(x: 80, y: 50, width: 64, height: 48))
        ]
        for (source, destination) in cases {
            guard let flight = ViewedCardFlight(source: source, destination: destination) else {
                fatalError("Valid measured rectangles must create a flight")
            }
            let start = flight.sample(at: 0)
            expectNear(start.scale, 1, "Flight begins at the original card scale")
            expect(start.offset == .zero, "Flight begins at the original card center")
            expectNear(start.maskHeight, source.height, "Flight initially preserves the whole card")
            expectNear(start.coverBlend, 0, "Flight initially preserves the playing media")
            let end = flight.sample(at: 1)
            expectNear(source.midX + end.offset.width, destination.midX, "Flight lands at the measured thumbnail center X")
            expectNear(source.midY + end.offset.height, destination.midY, "Flight lands at the measured thumbnail center Y")
            expectNear(source.width * end.scale, destination.width, "Flight ends at the measured thumbnail width")
            expectNear(end.maskHeight * end.scale, destination.height, "Flight ends at the measured thumbnail height")
            expectNear(end.coverBlend, 1, "Endpoint displays the same hero image as Viewed")
            for progress in stride(from: 0.0, through: 1.0, by: 0.025) {
                let sample = flight.sample(at: CGFloat(progress))
                expect([sample.scale, sample.offset.width, sample.offset.height, sample.maskHeight,
                        sample.cornerRadius, sample.coverBlend].allSatisfy(\.isFinite), "Every in-flight sample must remain finite")
                expect(sample.scale > 0 && sample.maskHeight > 0 && sample.cornerRadius > 0,
                       "Morph cannot invert or collapse the visible card")
                expect((0...1).contains(sample.coverBlend), "Hero blend stays within visible opacity bounds")
            }
            for invalidProgress: CGFloat in [-2, -.infinity, .infinity, .nan] {
                let clamped = flight.sample(at: invalidProgress)
                expectNear(clamped.scale, start.scale, "Negative/nonfinite progress safely returns the original card")
                expect(clamped.offset == start.offset, "Negative/nonfinite progress cannot move the card offscreen")
            }
            let overshoot = flight.sample(at: 1.1)
            expectNear(overshoot.scale, end.scale, "Animation overshoot cannot shrink beyond its destination")
            expect(overshoot.offset == end.offset, "Animation overshoot cannot travel past its destination")
        }

        let valid = CGRect(x: 16, y: 100, width: 358, height: 500)
        let invalid: [CGRect] = [
            .zero, .null, .infinite,
            CGRect(x: 0, y: 0, width: 0, height: 46),
            CGRect(x: 0, y: 0, width: 46, height: 0),
            CGRect(x: 0, y: 0, width: -46, height: 46),
            CGRect(x: 0, y: 0, width: 46, height: -46),
            CGRect(x: CGFloat.nan, y: 0, width: 46, height: 46),
            CGRect(x: 0, y: CGFloat.infinity, width: 46, height: 46),
            CGRect(x: CGFloat.greatestFiniteMagnitude, y: 0,
                   width: CGFloat.greatestFiniteMagnitude, height: 46)
        ]
        for frame in invalid {
            expect(ViewedCardFlight(source: frame, destination: valid) == nil, "Invalid source geometry must prevent flight")
            expect(ViewedCardFlight(source: valid, destination: frame) == nil, "Invalid target geometry must prevent flight")
        }
    }

    static func main() {
        testViewedFlightGeometry()
        // All cases exercise the production helpers extracted by the runner.
        var clock = PlayerMediaPlaybackClock()
        clock.tick(now: 100, itemCount: 2, loops: false)
        clock.tick(now: 109.9, itemCount: 2, loops: false)
        expect(clock.itemIndex == 0 && !clock.isComplete, "First media must receive its full ten seconds")
        clock.tick(now: 110, itemCount: 2, loops: false)
        expect(clock.itemIndex == 1 && clock.progress == 0 && !clock.isComplete, "Second media starts fresh")
        clock.tick(now: 119.9, itemCount: 2, loops: false)
        expect(!clock.isComplete, "Completion waits for the final media's full duration")
        clock.tick(now: 120, itemCount: 2, loops: false)
        expect(clock.isComplete && clock.progress == 1, "Final media completes the sequence")
        clock.tick(now: 999, itemCount: 2, loops: false)
        expect(clock.itemIndex == 1 && clock.elapsed == 10, "Completed playback cannot advance twice")

        clock = PlayerMediaPlaybackClock()
        clock.tick(now: 0, itemCount: 1, loops: false)
        clock.tick(now: 4, itemCount: 1, loops: false)
        clock.pause()
        clock.tick(now: 604, itemCount: 1, loops: false)
        expect(clock.elapsed == 4 && !clock.isComplete, "Background time must not count toward playback")
        clock.tick(now: 609, itemCount: 1, loops: false)
        expect(clock.elapsed == 9 && !clock.isComplete, "Playback resumes the remaining duration")
        clock.pause()
        clock.pause()
        clock.tick(now: 1000, itemCount: 1, loops: false)
        clock.tick(now: 1001, itemCount: 1, loops: false)
        expect(clock.isComplete, "Repeated pauses preserve visible elapsed time")

        clock = PlayerMediaPlaybackClock()
        clock.tick(now: 0, itemCount: 0, loops: false)
        clock.tick(now: 9.9, itemCount: 0, loops: false)
        expect(!clock.isComplete, "No-media placeholder still gets ten seconds")
        clock.tick(now: 10, itemCount: 0, loops: false)
        expect(clock.isComplete && clock.itemIndex == 0, "No-media placeholder completes once")

        clock = PlayerMediaPlaybackClock()
        for time in stride(from: 0, through: 50, by: 10) {
            clock.tick(now: Double(time), itemCount: 12, loops: false)
        }
        expect(clock.itemIndex == 5 && !clock.isComplete, "Sixth media remains visible for its duration")
        clock.tick(now: 60, itemCount: 12, loops: false)
        expect(clock.isComplete, "Card media sequence is capped at six items")

        clock = PlayerMediaPlaybackClock()
        clock.tick(now: 0, itemCount: 3, loops: false)
        clock.tick(now: 35, itemCount: 3, loops: false)
        expect(clock.itemIndex == 1 && clock.progress == 0, "Delayed timer delivery must not skip unseen media")

        clock = PlayerMediaPlaybackClock()
        for time in stride(from: 0, through: 40, by: 10) {
            clock.tick(now: Double(time), itemCount: 2, loops: true)
        }
        expect(clock.itemIndex == 0 && clock.progress == 0 && !clock.isComplete, "Shared profile/likes playback continues looping")
        clock = PlayerMediaPlaybackClock()
        clock.tick(now: 500, itemCount: 1, loops: false)
        expect(clock.itemIndex == 0 && clock.progress == 0 && !clock.isComplete, "Promoted/reset card has a fresh clock")

        var queue = ViewedPlayerQueue()
        expect(queue.orderedIDs([]).isEmpty, "Empty candidate set remains empty")
        expect(queue.orderedIDs(["a", "b", "c"]) == ["a", "b", "c"], "Initial server ordering is preserved")
        queue.deferPlayer("a")
        expect(queue.orderedIDs(["a", "b", "c"]) == ["b", "c", "a"], "Viewed player moves behind unseen candidates")
        queue.deferPlayer("b")
        expect(queue.orderedIDs(["a", "b", "c"]) == ["c", "a", "b"], "Unseen players retain priority")
        queue.deferPlayer("c")
        expect(queue.orderedIDs(["a", "b", "c"]) == ["a", "b", "c"], "Exhausted queue allows revisiting")
        queue.deferPlayer("a")
        expect(queue.orderedIDs(["a", "b", "c"]) == ["b", "c", "a"], "Revisits rotate without losing candidates")
        queue.deferPlayer("a")
        expect(queue.viewedIDs == ["b", "c", "a"], "Repeated completion never duplicates a player")
        expect(queue.orderedIDs(["a", "b", "c", "new"]) == ["new", "b", "c", "a"], "Refresh introduces new players ahead of viewed players")
        expect(queue.orderedIDs(["a", "c"]) == ["c", "a"], "Removed/explicitly-swiped players are not resurrected")
        expect(queue.orderedIDs(["a"]) == ["a"], "A lone player remains available")
        expect(queue.orderedIDs([]).isEmpty, "Stale viewed IDs cannot repopulate an empty deck")
        queue = ViewedPlayerQueue()
        expect(queue.orderedIDs(["a", "b", "c"]) == ["a", "b", "c"], "New account/filter context resets local ordering")

        expect(queue.newestViewedIDs(["a", "b"]).isEmpty, "Viewed strip is hidden before any completion")
        queue.deferPlayer("a")
        expect(queue.newestViewedIDs(["a"]) == ["a"], "Completed singleton remains available in viewed history")
        queue.deferPlayer("b")
        queue.deferPlayer("c")
        expect(queue.newestViewedIDs(["a", "b", "c"]) == ["c", "b", "a"], "Strip shows newest viewed player first")
        expect(queue.orderedIDs(["a", "b", "c"]) == ["a", "b", "c"], "Newest-first strip does not alter deck rotation order")
        queue.deferPlayer("a")
        expect(queue.newestViewedIDs(["a", "b", "c"]) == ["a", "c", "b"], "Replayed completion moves the unique history entry to the front")
        expect(queue.newestViewedIDs(["a", "b", "c"]).count == 3, "Repeated views never duplicate a history entry")
        expect(queue.newestViewedIDs(["a", "new"]) == ["a"], "History only exposes viewed players still eligible in this roster")
        expect(queue.newestViewedIDs([]).isEmpty, "No stale history buttons remain when all candidates disappear")
        queue.remove("a")
        expect(queue.newestViewedIDs(["a", "b", "c"]) == ["c", "b"], "Explicit removal cannot reappear in history after a stale same-scope roster refresh")
        expect(!queue.viewedIDs.contains("a"), "Explicit removal deletes its history ID, not merely its current tile")
        queue.remove("a")
        queue.remove("unknown")
        expect(queue.newestViewedIDs(["b", "c"]) == ["c", "b"], "Repeated or unknown removals preserve other viewed players")
        queue.remove("b")
        queue.remove("c")
        expect(queue.newestViewedIDs(["a", "b", "c"]).isEmpty, "Removing the last viewed player hides the strip")
        print("PASS: \(assertions) player auto-advance state assertions")
    }
}

import Foundation

actor MediaGate {
    var continuation: CheckedContinuation<Data, Never>?
    var count = 0
    func wait() async -> Data {
        count += 1
        return await withCheckedContinuation { continuation = $0 }
    }
    func isWaiting() -> Bool { continuation != nil }
    func release(_ value: String) { continuation?.resume(returning: Data(value.utf8)); continuation = nil }
}

@main
struct MediaLifecycleTests {
    static func main() async throws {
        let pipeline = RemoteImagePipeline()
        let oldGate = MediaGate()
        let newGate = MediaGate()
        func request(_ gate: MediaGate) -> RemoteImageRequest {
            RemoteImageRequest(source: RemoteImageSource(key: "private-attachment") { _ in await gate.wait() }, pointSize: CGSize(width: 100, height: 100), scale: 1, contentMode: .fit)
        }
        let oldRequest = request(oldGate)
        let oldTask = Task { try await pipeline.image(for: oldRequest) }
        while !(await oldGate.isWaiting()) { await Task.yield() }
        pipeline.clear()
        let newRequest = request(newGate)
        let newTask = Task { try await pipeline.image(for: newRequest) }
        while !(await newGate.isWaiting()) { await Task.yield() }
        await oldGate.release("private A")
        do {
            _ = try await oldTask.value
            fatalError("A late private image must be cancelled after logout")
        } catch is CancellationError {}
        guard pipeline.cachedImage(for: oldRequest) == nil else { fatalError("A late old image must not repopulate cleared cache") }
        // The stale task's defer must not delete the replacement task using the same key.
        let duplicateTask = Task { try await pipeline.image(for: newRequest) }
        await newGate.release("private B")
        let next = try await newTask.value
        let duplicate = try await duplicateTask.value
        guard next.label == "private B" && duplicate.label == "private B" else { fatalError("Only new-account media can be returned") }
        guard await newGate.count == 1 else { fatalError("Concurrent new-account requests must keep deduplicating") }
        guard pipeline.cachedImage(for: newRequest)?.label == "private B" else { fatalError("New account retains its own image") }
        pipeline.clear()
        guard pipeline.cachedImage(for: newRequest) == nil else { fatalError("Logout removes cached authenticated images") }
        print("Media lifecycle tests: 6 checks passed")
    }
}

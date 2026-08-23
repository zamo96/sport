import SwiftUI

@MainActor
final class BookingCallFlow: ObservableObject {
    @Published var isResultPresented = false

    private var attemptID: UUID?
    private var wasOpenAccepted = false
    private var didEnterBackground = false
    private var didReturnToActive = false
    private var timeoutTask: Task<Void, Never>?

    func start(url: URL, openURL: OpenURLAction) {
        reset()

        let nextAttemptID = UUID()
        attemptID = nextAttemptID

        openURL(url) { [weak self] accepted in
            Task { @MainActor in
                guard let self, self.attemptID == nextAttemptID else {
                    return
                }
                guard accepted else {
                    self.resetTracking()
                    return
                }
                self.wasOpenAccepted = true
                self.presentResultIfReady()
            }
        }

        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled else {
                return
            }
            await MainActor.run {
                guard let self,
                      self.attemptID == nextAttemptID,
                      !self.didEnterBackground else {
                    return
                }
                self.resetTracking()
            }
        }
    }

    func handle(scenePhase: ScenePhase) {
        guard attemptID != nil else {
            return
        }

        switch scenePhase {
        case .background:
            didEnterBackground = true
            presentResultIfReady()
        case .active:
            guard didEnterBackground else {
                return
            }
            didReturnToActive = true
            presentResultIfReady()
        case .inactive:
            break
        @unknown default:
            break
        }
    }

    func reset() {
        isResultPresented = false
        resetTracking()
    }

    private func presentResultIfReady() {
        guard wasOpenAccepted,
              didEnterBackground,
              didReturnToActive,
              !isResultPresented else {
            return
        }

        resetTracking()
        isResultPresented = true
    }

    private func resetTracking() {
        timeoutTask?.cancel()
        timeoutTask = nil
        attemptID = nil
        wasOpenAccepted = false
        didEnterBackground = false
        didReturnToActive = false
    }
}

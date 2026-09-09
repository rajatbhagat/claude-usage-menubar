import Foundation

@MainActor
final class PlanUsageStore: ObservableObject {
    @Published private(set) var snapshot: PlanUsageSnapshot?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var liveNumbersUnavailable = false
    @Published private(set) var isRefreshing = false

    private var timer: Timer?
    private var fetchInFlight = false

    init() {
        refresh()
        // Usage can climb several percent per minute under heavy use, so poll
        // every 30s. The call is free (zero model cost) and cheap (~300ms).
        let timer = Timer(timeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        // .common, not the default mode: a timer in the default run loop mode
        // stops firing while a menu or popover is open, which is exactly when
        // the user is looking at the numbers.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func refresh() {
        guard !fetchInFlight else { return }
        fetchInFlight = true
        isRefreshing = true
        PlanUsageFetcher.fetch { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.fetchInFlight = false
                self.isRefreshing = false
                switch result {
                case .success(let snapshot):
                    self.snapshot = snapshot
                    self.lastError = nil
                    self.liveNumbersUnavailable = false
                    self.lastUpdated = Date()
                case .failure(let error):
                    if case PlanUsageError.noLiveNumbers = error {
                        self.liveNumbersUnavailable = true
                        self.lastError = nil
                    } else {
                        self.liveNumbersUnavailable = false
                        self.lastError = String(describing: error)
                    }
                }
            }
        }
    }
}

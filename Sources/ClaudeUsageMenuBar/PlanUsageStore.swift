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
        // Plan usage percentages move slowly; polling every 60s keeps the menu
        // bar current without spawning the `claude` CLI more than needed.
        timer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
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

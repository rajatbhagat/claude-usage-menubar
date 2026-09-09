import Foundation
import Combine

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var todayTotal = ModelUsage()
    @Published private(set) var todayCost: Double = 0
    @Published private(set) var todayByModel: [String: ModelUsage] = [:]
    @Published private(set) var sessionTotal = ModelUsage()
    @Published private(set) var sessionCost: Double = 0
    @Published private(set) var activeSessionId: String?
    @Published private(set) var lastUpdated = Date()
    @Published private(set) var hasUnknownModelPricing = false

    private let scanner = LogScanner()
    private var seenKeys = Set<String>()
    private var sessionLastSeen: [String: Date] = [:]
    private var sessionUsage: [String: ModelUsage] = [:]
    private var sessionCosts: [String: Double] = [:]
    private var currentDayKey = UsageStore.dayKey(for: Date())
    private var timer: Timer?

    var menuBarTitle: String {
        "\(formatTokens(todayTotal.totalTokens)) · \(formatCost(todayCost))"
    }

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.refresh() }
        }
    }

    func refresh() {
        let events = scanner.scan()
        guard !events.isEmpty else { return }

        for event in events {
            guard !seenKeys.contains(event.dedupKey) else { continue }
            seenKeys.insert(event.dedupKey)

            let eventDayKey = Self.dayKey(for: event.timestamp)
            if eventDayKey > currentDayKey {
                currentDayKey = eventDayKey
                todayTotal = ModelUsage()
                todayByModel = [:]
                todayCost = 0
            }
            if eventDayKey == currentDayKey {
                todayTotal += event
                var modelUsage = todayByModel[event.model] ?? ModelUsage()
                modelUsage += event
                todayByModel[event.model] = modelUsage
                if let c = cost(for: event) {
                    todayCost += c
                } else {
                    hasUnknownModelPricing = true
                }
            }

            sessionLastSeen[event.sessionId] = event.timestamp
            var su = sessionUsage[event.sessionId] ?? ModelUsage()
            su += event
            sessionUsage[event.sessionId] = su
            sessionCosts[event.sessionId, default: 0] += cost(for: event) ?? 0
        }

        if let latest = sessionLastSeen.max(by: { $0.value < $1.value })?.key {
            activeSessionId = latest
            sessionTotal = sessionUsage[latest] ?? ModelUsage()
            sessionCost = sessionCosts[latest] ?? 0
        }

        lastUpdated = Date()
    }

    static func dayKey(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f.string(from: date)
    }
}

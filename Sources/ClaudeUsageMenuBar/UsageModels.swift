import Foundation

/// Aggregated token counts for some scope (a day, a model, a session).
struct ModelUsage {
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheCreationTokens: Int = 0
    var cacheReadTokens: Int = 0

    var totalTokens: Int {
        inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens
    }

    static func += (lhs: inout ModelUsage, rhs: UsageEvent) {
        lhs.inputTokens += rhs.inputTokens
        lhs.outputTokens += rhs.outputTokens
        lhs.cacheCreationTokens += rhs.cacheCreationTokens
        lhs.cacheReadTokens += rhs.cacheReadTokens
    }
}

/// One assistant-turn usage record parsed from a Claude Code session log line.
struct UsageEvent {
    let timestamp: Date
    let sessionId: String
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    /// Dedup key: prefer requestId (one per API call); fall back to the line's uuid.
    let dedupKey: String
}

struct ModelPricing {
    let inputPerM: Double
    let outputPerM: Double
    let cacheWritePerM: Double
    let cacheReadPerM: Double
}

/// Anthropic first-party API pricing per 1M tokens.
/// Cache write ~1.25x input rate, cache read ~0.1x input rate (standard ratio).
let pricingTable: [String: ModelPricing] = [
    "claude-sonnet-5": ModelPricing(inputPerM: 2.00, outputPerM: 10.00, cacheWritePerM: 2.50, cacheReadPerM: 0.20),
    "claude-opus-5": ModelPricing(inputPerM: 5.00, outputPerM: 25.00, cacheWritePerM: 6.25, cacheReadPerM: 0.50),
    "claude-haiku-4-5": ModelPricing(inputPerM: 1.00, outputPerM: 5.00, cacheWritePerM: 1.25, cacheReadPerM: 0.10),
    "claude-sonnet-4-6": ModelPricing(inputPerM: 3.00, outputPerM: 15.00, cacheWritePerM: 3.75, cacheReadPerM: 0.30),
    "claude-opus-4-8": ModelPricing(inputPerM: 5.00, outputPerM: 25.00, cacheWritePerM: 6.25, cacheReadPerM: 0.50),
    "claude-opus-4-7": ModelPricing(inputPerM: 5.00, outputPerM: 25.00, cacheWritePerM: 6.25, cacheReadPerM: 0.50),
    "claude-opus-4-6": ModelPricing(inputPerM: 5.00, outputPerM: 25.00, cacheWritePerM: 6.25, cacheReadPerM: 0.50),
    "claude-fable-5-1": ModelPricing(inputPerM: 10.00, outputPerM: 50.00, cacheWritePerM: 12.50, cacheReadPerM: 0.25),
    "claude-fable-5": ModelPricing(inputPerM: 10.00, outputPerM: 50.00, cacheWritePerM: 12.50, cacheReadPerM: 1.00),
]

func cost(for event: UsageEvent) -> Double? {
    guard let pricing = pricingTable[event.model] else { return nil }
    let inputCost = Double(event.inputTokens) / 1_000_000 * pricing.inputPerM
    let outputCost = Double(event.outputTokens) / 1_000_000 * pricing.outputPerM
    let cacheWriteCost = Double(event.cacheCreationTokens) / 1_000_000 * pricing.cacheWritePerM
    let cacheReadCost = Double(event.cacheReadTokens) / 1_000_000 * pricing.cacheReadPerM
    return inputCost + outputCost + cacheWriteCost + cacheReadCost
}

func formatTokens(_ n: Int) -> String {
    if n >= 1_000_000 { return String(format: "%.2fM", Double(n) / 1_000_000) }
    if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
    return "\(n)"
}

func formatCost(_ c: Double) -> String {
    String(format: "$%.2f", c)
}

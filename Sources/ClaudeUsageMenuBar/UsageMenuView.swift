import SwiftUI

struct UsageMenuView: View {
    @ObservedObject var store: UsageStore

    private let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            Divider()

            section(title: "Today") {
                usageRow("Input", store.todayTotal.inputTokens)
                usageRow("Output", store.todayTotal.outputTokens)
                usageRow("Cache write", store.todayTotal.cacheCreationTokens)
                usageRow("Cache read", store.todayTotal.cacheReadTokens)
            }

            if !store.todayByModel.isEmpty {
                Divider()
                section(title: "By model") {
                    ForEach(store.todayByModel.keys.sorted(), id: \.self) { model in
                        let usage = store.todayByModel[model] ?? ModelUsage()
                        HStack {
                            Text(model)
                                .font(.system(size: 11, design: .monospaced))
                            Spacer()
                            Text(formatTokens(usage.totalTokens))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if let sessionId = store.activeSessionId {
                Divider()
                section(title: "Current session") {
                    Text(String(sessionId.prefix(8)))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                    HStack {
                        Text("\(formatTokens(store.sessionTotal.totalTokens)) tokens")
                        Spacer()
                        Text(formatCost(store.sessionCost))
                    }
                    .font(.system(size: 12))
                }
            }

            if store.hasUnknownModelPricing {
                Text("Some models have no known pricing — cost shown is a lower bound.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Text("Updated \(relativeFormatter.localizedString(for: store.lastUpdated, relativeTo: Date()))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Refresh") { store.refresh() }
                    .font(.system(size: 11))
            }

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(width: 260)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Claude Usage Today")
                .font(.headline)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(formatTokens(store.todayTotal.totalTokens))
                    .font(.system(size: 22, weight: .semibold))
                Text("tokens")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Text("Est. cost: \(formatCost(store.todayCost))")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func usageRow(_ label: String, _ tokens: Int) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
            Spacer()
            Text(formatTokens(tokens))
                .font(.system(size: 12, design: .monospaced))
        }
    }
}

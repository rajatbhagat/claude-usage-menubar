import SwiftUI

struct UsageMenuView: View {
    @ObservedObject var planStore: PlanUsageStore
    @ObservedObject var localStore: UsageStore

    /// "Updated 12s ago" / "Updated just now". Deliberately not
    /// RelativeDateTimeFormatter, which renders a moment ago as "in 0 seconds".
    private func updatedText(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 5 { return "Updated just now" }
        if seconds < 60 { return "Updated \(seconds)s ago" }
        let minutes = seconds / 60
        return "Updated \(minutes)m ago"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Plan Usage Limits")
                .font(.headline)

            if let snapshot = planStore.snapshot {
                planRow(title: "Current session", percent: snapshot.sessionPercent, resetsAt: snapshot.sessionResetsAt, resetRaw: snapshot.sessionResetRaw)
                if let weekPercent = snapshot.weekPercent {
                    planRow(title: "Current week (all models)", percent: weekPercent, resetsAt: snapshot.weekResetsAt, resetRaw: snapshot.weekResetRaw)
                }
            } else if planStore.liveNumbersUnavailable {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Live percentages unavailable right now").font(.system(size: 12, weight: .semibold))
                    Text("claude /usage didn't include them this check — it'll keep retrying. Local stats below are still accurate.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            } else if let error = planStore.lastError {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Couldn't read plan usage").font(.system(size: 12, weight: .semibold))
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }
            } else {
                Text("Loading…").font(.system(size: 12)).foregroundStyle(.secondary)
            }

            Divider()

            section(title: "Local logs today (approx.)") {
                HStack {
                    Text("\(formatTokens(localStore.todayTotal.totalTokens)) tokens")
                    Spacer()
                    Text(formatCost(localStore.todayCost))
                }
                .font(.system(size: 12))
            }

            Divider()

            HStack {
                if planStore.isRefreshing {
                    Text("Refreshing…")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                } else if let updated = planStore.lastUpdated {
                    Text(updatedText(updated))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                } else {
                    Text(" ").font(.system(size: 10))
                }
                Spacer()
                Button("Refresh") {
                    planStore.refresh()
                    localStore.refresh()
                }
                .font(.system(size: 11))
            }

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(width: 280)
        // Refresh on open, so the numbers are current at the moment you look
        // rather than up to one poll interval stale.
        .onAppear {
            planStore.refresh()
            localStore.refresh()
        }
    }

    private func planRow(title: String, percent: Int, resetsAt: Date?, resetRaw: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            HStack(spacing: 8) {
                UsageBarGauge(percent: percent)
                Text("\(percent)%")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .frame(width: 34, alignment: .trailing)
            }
            Text(resetsAt != nil ? formatCountdown(to: resetsAt) : "Resets \(resetRaw)")
                .font(.system(size: 10))
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
}

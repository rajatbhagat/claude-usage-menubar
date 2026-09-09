import SwiftUI

func gaugeColor(for percent: Int) -> Color {
    switch percent {
    case ..<60: return .green
    case 60..<85: return .yellow
    default: return .red
    }
}

/// Compact ring gauge sized for the menu bar itself.
struct MenuBarRingGauge: View {
    let percent: Int?

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.3), lineWidth: 2.5)
            if let percent {
                Circle()
                    .trim(from: 0, to: CGFloat(min(max(percent, 0), 100)) / 100)
                    .stroke(gaugeColor(for: percent), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: 15, height: 15)
    }
}

/// Horizontal bar gauge for the detail popover, matching claude.ai's usage panel.
struct UsageBarGauge: View {
    let percent: Int

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(gaugeColor(for: percent).opacity(0.25))
                RoundedRectangle(cornerRadius: 3)
                    .fill(gaugeColor(for: percent))
                    .frame(width: geo.size.width * CGFloat(min(max(percent, 0), 100)) / 100)
            }
        }
        .frame(height: 6)
    }
}

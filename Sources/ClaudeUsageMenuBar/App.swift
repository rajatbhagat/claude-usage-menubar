import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only — no Dock icon, no app switcher entry.
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct ClaudeUsageMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var planStore = PlanUsageStore()
    @StateObject private var localStore = UsageStore()

    var body: some Scene {
        MenuBarExtra {
            UsageMenuView(planStore: planStore, localStore: localStore)
        } label: {
            HStack(spacing: 4) {
                MenuBarRingGauge(percent: planStore.snapshot?.sessionPercent)
                if let percent = planStore.snapshot?.sessionPercent {
                    Text("\(percent)%")
                } else {
                    Text("–")
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}

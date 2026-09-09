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
    @StateObject private var store = UsageStore()

    var body: some Scene {
        MenuBarExtra {
            UsageMenuView(store: store)
        } label: {
            Text(store.menuBarTitle)
        }
        .menuBarExtraStyle(.window)
    }
}

import SwiftUI
import app_mixzer
@preconcurrency import UserNotifications
#if canImport(AppKit)
import AppKit
#endif

class AppRunnerDelegate: NSObject, NSApplicationDelegate {
    // track whether we've auto-focused during this app session
    @MainActor private static var hasAutoFocusedThisSession: Bool = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Observe when any window becomes key and forward a focus request to the sidebar search
    NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { _ in
            // Defer to main thread to access main-actor-isolated state safely
            DispatchQueue.main.async {
                // only attempt auto-focus once per session and only if user preference allows it
                let userPref = UserDefaults.standard.object(forKey: "autoFocusSidebarOnLaunch") as? Bool ?? true
                guard userPref, !AppRunnerDelegate.hasAutoFocusedThisSession else { return }

                // Try to perform a cautious auto-focus: check firstResponder and retry a few times if window still initializing.
                func attempt(_ triesLeft: Int, delay: TimeInterval) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        guard let key = NSApp.keyWindow else {
                            if triesLeft > 0 { attempt(triesLeft - 1, delay: 0.08) }
                            return
                        }

                        // Don't steal focus if the user is currently typing.
                        if let fr = key.firstResponder, (fr is NSTextView || fr is NSTextField || fr is NSSearchField) {
                            // user is interacting with a text input; skip auto-focus
                            return
                        }

                        // Only target our main AppRunner window title to avoid unrelated windows
                        if key.title == "AppRunner" {
                            NotificationCenter.default.post(name: .appMixzerFocusSidebarSearch, object: nil)
                            AppRunnerDelegate.hasAutoFocusedThisSession = true
                        } else if triesLeft > 0 {
                            attempt(triesLeft - 1, delay: 0.08)
                        }
                    }
                }

                attempt(3, delay: 0.05)
            }
        }

        // Insert a precise Edit->Find -> Focus Search menu item using AppKit so it appears exactly where users expect
        DispatchQueue.main.async {
            guard let mainMenu = NSApp.mainMenu,
                  let editItem = mainMenu.item(withTitle: "Edit"),
                  let editSubmenu = editItem.submenu else { return }

            // Find the 'Find' submenu (may be localized; try common title first)
            let findItem = editSubmenu.items.first(where: { $0.title == "Find" || $0.title == "查找" || $0.title == "搜尋" })
            if let findMenuItem = findItem, let findSubmenu = findMenuItem.submenu {
                // Avoid duplicate insertion
                if findSubmenu.items.first(where: { $0.representedObject as? String == "appmixzer.focussearch" }) == nil {
                    let mi = NSMenuItem(title: "Focus Search", action: #selector(AppRunnerDelegate.focusSearchMenuAction(_:)), keyEquivalent: "f")
                    mi.keyEquivalentModifierMask = [.command]
                    mi.target = self
                    mi.representedObject = "appmixzer.focussearch"
                    // Insert near top so it's discoverable
                    findSubmenu.insertItem(mi, at: 0)
                }
            }
        }
    }

    @objc func focusSearchMenuAction(_ sender: Any?) {
        NotificationCenter.default.post(name: .appMixzerFocusSidebarSearch, object: nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
    }
}

@main
struct AppRunnerApp: App {
    @NSApplicationDelegateAdaptor(AppRunnerDelegate.self) private var appDelegate

    init() {
        // register notification delegate early so notification actions can be handled,
        // but only when running as a bundled .app (UNUserNotificationCenter expects a valid app bundle)
        let isBundledApp = Bundle.main.bundleURL.pathExtension.lowercased() == "app"
        if isBundledApp {
            UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        } else {
            SimpleLogger.log("UNUserNotificationCenter registration skipped: not running as .app bundle")
        }
    }

    var body: some Scene {
        WindowGroup("AppRunner") {
            RankingsView()
                .task {
                    // Temporary startup check: attempt to load ranking and write result to a log file for debug
                    let svc = RankingService()
                    let items = await svc.loadRanking()
                    SimpleLogger.log("DEBUG: AppRunner startup -> loaded ranking items count: \(items.count)")
                }
        }
        .commands {
            FocusSearchCommands()
        }
    }
}

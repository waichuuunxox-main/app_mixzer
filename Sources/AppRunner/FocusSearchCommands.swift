import SwiftUI
import app_mixzer
#if canImport(AppKit)
import AppKit
#endif

struct FocusSearchCommands: Commands {
    var body: some Commands {
        // Keep a dedicated Search menu for discoverability
        CommandMenu("Search") {
            Button("Focus Search") {
                NotificationCenter.default.post(name: .appMixzerFocusSidebarSearch, object: nil)
            }
            .keyboardShortcut("f", modifiers: .command)
        }

        // Also insert into the Edit -> Find command group to appear in standard locations
        CommandGroup(replacing: .textEditing) {
            Button("Focus Search") {
                NotificationCenter.default.post(name: .appMixzerFocusSidebarSearch, object: nil)
            }
            .keyboardShortcut("f", modifiers: .command)
        }
    }
}

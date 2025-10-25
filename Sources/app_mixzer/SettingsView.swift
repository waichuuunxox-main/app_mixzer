import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var debugEnabled: Bool = SimpleLogger.isDebug
    @AppStorage("compactSidebar") private var compactSidebar: Bool = false
    @AppStorage("autoFocusSidebarOnLaunch") private var autoFocusSidebarOnLaunch: Bool = true
    @AppStorage("showImageDebugOverlay") private var showImageDebugOverlay: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Text("Settings").font(.title2)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.bottom, 8)

            Toggle(isOn: $debugEnabled) {
                Text("Enable debug logging (writes to stderr)")
            }
            .onChange(of: debugEnabled) { _, newValue in
                SimpleLogger.setDebugEnabled(newValue)
            }


            Divider()

            Toggle(isOn: $compactSidebar) {
                VStack(alignment: .leading) {
                    Text("Compact sidebar")
                    Text("Enable compact list layout in the right-hand sidebar (smaller artwork, condensed rows).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Button {
                // Request focus for the sidebar search field
                NotificationCenter.default.post(name: .appMixzerFocusSidebarSearch, object: nil)
            } label: {
                Label("Focus Search", systemImage: "magnifyingglass")
            }

            Toggle(isOn: $autoFocusSidebarOnLaunch) {
                VStack(alignment: .leading) {
                    Text("Auto-focus sidebar search on launch")
                    Text("When enabled, the app will attempt to focus the sidebar search field once when the main window first becomes active.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Toggle(isOn: $showImageDebugOverlay) {
                VStack(alignment: .leading) {
                    Text("Show image debug overlay")
                    Text("When enabled (and debug logging is also enabled), images will show a small overlay with their URL and load state. Disable to hide status badges.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Text("Notes:")
            Text("- Debug logging can also be enabled via environment variable APP_MIXZER_DEBUG=1.")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding(16)
        .frame(minWidth: 360, minHeight: 160)
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}

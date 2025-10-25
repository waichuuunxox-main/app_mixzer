import SwiftUI

struct SettingsView: View {
    @State private var debugEnabled: Bool = SimpleLogger.isDebug

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings").font(.title2).padding(.bottom, 8)

            Toggle(isOn: $debugEnabled) {
                Text("Enable debug logging (writes to stderr)")
            }
            .onChange(of: debugEnabled) { newValue in
                SimpleLogger.setDebugEnabled(newValue)
            }

            Divider()

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

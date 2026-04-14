import SwiftUI

struct SettingsView: View {
    let preferences: Preferences

    @State private var mode: ConnectionMode
    @State private var host: String
    @State private var portText: String
    @State private var didSave = false

    init(preferences: Preferences) {
        self.preferences = preferences
        _mode = State(initialValue: preferences.connectionMode)
        _host = State(initialValue: preferences.directHost)
        _portText = State(initialValue: String(preferences.directPort))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GHSpacing.lg) {
                Text("Settings")
                    .font(GHTypography.titleLg)
                    .foregroundStyle(GHColors.textPrimary)

                GHCard {
                    VStack(alignment: .leading, spacing: GHSpacing.md) {
                        Text("Connection Mode")
                            .font(GHTypography.bodySm)
                            .foregroundStyle(GHColors.textSecondary)

                        Picker("Connection Mode", selection: $mode) {
                            Text("Direct LAN").tag(ConnectionMode.direct)
                            Text("Managed").tag(ConnectionMode.managed)
                        }
                        .pickerStyle(.segmented)

                        GHInput(title: "Host", text: $host, placeholder: "192.168.1.25")
                            .opacity(mode == .direct ? 1 : 0.6)

                        GHInput(title: "Port", text: $portText, placeholder: "9876")
                            .opacity(mode == .direct ? 1 : 0.6)

                        if let validationMessage {
                            GHBanner(
                                tone: .warning,
                                title: "Validation",
                                message: validationMessage
                            )
                        } else if didSave {
                            GHBanner(
                                tone: .success,
                                title: "Saved",
                                message: "Connection preferences updated."
                            )
                        }

                        GHButton(title: "Save Settings", icon: "checkmark", style: .primary) {
                            save()
                        }
                    }
                }
            }
            .padding(GHSpacing.xl)
        }
        .background(GHColors.bgPrimary)
    }

    private var validationMessage: String? {
        guard mode == .direct else { return nil }
        if host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Host is required for direct LAN mode."
        }
        guard let port = Int(portText), (1...65_535).contains(port) else {
            return "Port must be a number between 1 and 65535."
        }
        return nil
    }

    private func save() {
        guard validationMessage == nil else {
            didSave = false
            return
        }

        preferences.connectionMode = mode
        preferences.directHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        preferences.directPort = Int(portText) ?? preferences.directPort
        didSave = true
    }
}

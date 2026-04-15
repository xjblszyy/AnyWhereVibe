import SwiftUI

struct SettingsView: View {
    @ObservedObject var preferences: Preferences
    let connectionManager: ConnectionManager?

    @State private var mode: ConnectionMode
    @State private var host: String
    @State private var portText: String
    @State private var nodeURL: String
    @State private var authToken: String
    @State private var managedDevices: [Mrt_DeviceInfo] = []
    @State private var didSave = false

    init(preferences: Preferences, connectionManager: ConnectionManager? = nil) {
        self.preferences = preferences
        self.connectionManager = connectionManager
        _mode = State(initialValue: preferences.connectionMode)
        _host = State(initialValue: preferences.directHost)
        _portText = State(initialValue: String(preferences.directPort))
        _nodeURL = State(initialValue: preferences.nodeURL)
        _authToken = State(initialValue: preferences.authToken)
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

                        if mode == .direct {
                            GHInput(title: "Host", text: $host, placeholder: "192.168.1.25")
                            GHInput(title: "Port", text: $portText, placeholder: "9876")
                        } else {
                            GHInput(title: "Connection Node URL", text: $nodeURL, placeholder: "wss://relay.example.com/ws")
                            GHInput(title: "Auth Token", text: $authToken, placeholder: "mrt_ak_...")
                        }

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

                        if mode == .managed {
                            if managedDevices.isEmpty {
                                GHBanner(
                                    tone: .neutral,
                                    title: "No agents yet",
                                    message: "Save your node settings to load available desktop agents."
                                )
                            } else {
                                VStack(alignment: .leading, spacing: GHSpacing.sm) {
                                    Text("Available Agents")
                                        .font(GHTypography.bodySm)
                                        .foregroundStyle(GHColors.textSecondary)

                                    ForEach(managedDevices.filter { $0.deviceType == .agent }, id: \.deviceID) { device in
                                        GHCard {
                                            HStack(spacing: GHSpacing.sm) {
                                                VStack(alignment: .leading, spacing: GHSpacing.xs) {
                                                    Text(device.displayName.isEmpty ? device.deviceID : device.displayName)
                                                        .font(GHTypography.bodySm)
                                                        .foregroundStyle(GHColors.textPrimary)
                                                    Text(device.deviceID)
                                                        .font(GHTypography.caption)
                                                        .foregroundStyle(GHColors.textSecondary)
                                                }
                                                Spacer()
                                                GHButton(title: "Connect", icon: nil, style: .secondary) {
                                                    connect(device: device)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
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
        .onAppear {
            managedDevices = connectionManager?.devices.filter { $0.deviceType == .agent } ?? []
            connectionManager?.onDevicesChange = { devices in
                Task { @MainActor in
                    managedDevices = devices.filter { $0.deviceType == .agent }
                }
            }
        }
    }

    private var validationMessage: String? {
        settingsValidationMessage(
            mode: mode,
            host: host,
            portText: portText,
            nodeURL: nodeURL,
            authToken: authToken
        )
    }

    private func save() {
        guard validationMessage == nil else {
            didSave = false
            return
        }

        preferences.connectionMode = mode
        preferences.directHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        preferences.directPort = Int(portText) ?? preferences.directPort
        preferences.nodeURL = nodeURL.trimmingCharacters(in: .whitespacesAndNewlines)
        preferences.authToken = authToken.trimmingCharacters(in: .whitespacesAndNewlines)
        didSave = true

        guard mode == .managed, let connectionManager else {
            return
        }

        Task {
            try? await connectionManager.connectManaged(
                nodeURL: preferences.nodeURL,
                authToken: preferences.authToken,
                deviceID: UIDevice.current.identifierForVendor?.uuidString ?? "ios-phone",
                displayName: UIDevice.current.name,
                targetDeviceID: preferences.managedTargetDeviceID.isEmpty ? nil : preferences.managedTargetDeviceID
            )
            try? await Task.sleep(nanoseconds: 20_000_000)
            try? await connectionManager.requestDeviceList()
            await MainActor.run {
                managedDevices = connectionManager.devices.filter { $0.deviceType == .agent }
            }
        }
    }

    private func connect(device: Mrt_DeviceInfo) {
        preferences.managedTargetDeviceID = device.deviceID
        preferences.managedTargetDeviceName = device.displayName

        guard let connectionManager else {
            return
        }

        Task {
            try? await connectionManager.connectToDevice(targetDeviceID: device.deviceID)
        }
    }
}

func settingsValidationMessage(
    mode: ConnectionMode,
    host: String,
    portText: String,
    nodeURL: String,
    authToken: String
) -> String? {
    switch mode {
    case .direct:
        if host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Host is required for direct LAN mode."
        }
        guard let port = Int(portText), (1...65_535).contains(port) else {
            return "Port must be a number between 1 and 65535."
        }
        return nil
    case .managed:
        if nodeURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Connection Node URL is required for managed mode."
        }
        if authToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Auth token is required for managed mode."
        }
        return nil
    }
}

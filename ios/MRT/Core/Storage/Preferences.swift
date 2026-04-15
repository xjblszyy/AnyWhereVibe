import Foundation

enum ConnectionMode: String, Equatable {
    case direct
    case managed
}

final class Preferences: ObservableObject {
    private enum Keys {
        static let directHost = "direct.host"
        static let directPort = "direct.port"
        static let connectionMode = "connection.mode"
        static let nodeURL = "node.url"
        static let authToken = "node.auth_token"
        static let managedTargetDeviceID = "node.target_device_id"
        static let managedTargetDeviceName = "node.target_device_name"
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.directHost = userDefaults.string(forKey: Keys.directHost) ?? "127.0.0.1"
        let savedPort = userDefaults.integer(forKey: Keys.directPort)
        self.directPort = savedPort == 0 ? 9876 : savedPort
        self.nodeURL = userDefaults.string(forKey: Keys.nodeURL) ?? ""
        self.authToken = userDefaults.string(forKey: Keys.authToken) ?? ""
        self.managedTargetDeviceID = userDefaults.string(forKey: Keys.managedTargetDeviceID) ?? ""
        self.managedTargetDeviceName = userDefaults.string(forKey: Keys.managedTargetDeviceName) ?? ""
        if let rawValue = userDefaults.string(forKey: Keys.connectionMode),
           let mode = ConnectionMode(rawValue: rawValue) {
            self.connectionMode = mode
        } else {
            self.connectionMode = .direct
        }
    }

    @Published var directHost: String {
        didSet { userDefaults.set(directHost, forKey: Keys.directHost) }
    }

    @Published var directPort: Int {
        didSet { userDefaults.set(directPort, forKey: Keys.directPort) }
    }

    @Published var connectionMode: ConnectionMode {
        didSet { userDefaults.set(connectionMode.rawValue, forKey: Keys.connectionMode) }
    }

    @Published var nodeURL: String {
        didSet { userDefaults.set(nodeURL, forKey: Keys.nodeURL) }
    }

    @Published var authToken: String {
        didSet { userDefaults.set(authToken, forKey: Keys.authToken) }
    }

    @Published var managedTargetDeviceID: String {
        didSet { userDefaults.set(managedTargetDeviceID, forKey: Keys.managedTargetDeviceID) }
    }

    @Published var managedTargetDeviceName: String {
        didSet { userDefaults.set(managedTargetDeviceName, forKey: Keys.managedTargetDeviceName) }
    }

    var connectionConfigurationSignature: String {
        "\(connectionMode.rawValue)|\(directHost)|\(directPort)|\(nodeURL)|\(authToken)|\(managedTargetDeviceID)|\(managedTargetDeviceName)"
    }
}

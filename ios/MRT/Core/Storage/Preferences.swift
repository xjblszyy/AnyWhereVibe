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
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.directHost = userDefaults.string(forKey: Keys.directHost) ?? "127.0.0.1"
        let savedPort = userDefaults.integer(forKey: Keys.directPort)
        self.directPort = savedPort == 0 ? 9876 : savedPort
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

    var connectionConfigurationSignature: String {
        "\(connectionMode.rawValue)|\(directHost)|\(directPort)"
    }
}

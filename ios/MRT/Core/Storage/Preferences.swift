import Foundation

enum ConnectionMode: String, Equatable {
    case direct
    case managed
}

final class Preferences {
    private enum Keys {
        static let directHost = "direct.host"
        static let directPort = "direct.port"
        static let connectionMode = "connection.mode"
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var directHost: String {
        get { userDefaults.string(forKey: Keys.directHost) ?? "127.0.0.1" }
        set { userDefaults.set(newValue, forKey: Keys.directHost) }
    }

    var directPort: Int {
        get {
            let value = userDefaults.integer(forKey: Keys.directPort)
            return value == 0 ? 9876 : value
        }
        set { userDefaults.set(newValue, forKey: Keys.directPort) }
    }

    var connectionMode: ConnectionMode {
        get {
            guard let rawValue = userDefaults.string(forKey: Keys.connectionMode),
                  let mode = ConnectionMode(rawValue: rawValue) else {
                return .direct
            }
            return mode
        }
        set { userDefaults.set(newValue.rawValue, forKey: Keys.connectionMode) }
    }
}

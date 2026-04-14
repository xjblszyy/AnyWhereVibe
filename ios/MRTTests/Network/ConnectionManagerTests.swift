@testable import MRT
import XCTest

final class ConnectionManagerTests: XCTestCase {
    func testConnectionManagerConnectsToSocketURLSendsHandshakeAndWaitsForAgentInfo() async throws {
        let socket = StubWebSocketClient()
        let manager = ConnectionManager(socket: socket, heartbeatInterval: 15, timeoutInterval: 45)

        try await manager.connect(host: "127.0.0.1", port: 9876)

        XCTAssertEqual(socket.connectedURL?.absoluteString, "ws://127.0.0.1:9876/")
        XCTAssertEqual(manager.state, .connecting)
        XCTAssertEqual(socket.sentData.count, 1)
        let handshake = try ProtobufCodec.decode(socket.sentData[0])
        if case .handshake = handshake.payload {
        } else {
            XCTFail("Expected handshake envelope")
        }

        socket.pushIncomingEnvelope(makeAgentInfoEnvelope())

        XCTAssertEqual(manager.state, .connected)
    }

    func testConnectionManagerReconnectsOnSocketClose() async throws {
        let socket = StubWebSocketClient()
        let manager = ConnectionManager(socket: socket, heartbeatInterval: 15, timeoutInterval: 45)

        try await manager.connect(host: "127.0.0.1", port: 9876)
        socket.pushIncomingEnvelope(makeAgentInfoEnvelope())

        socket.simulateClose()

        XCTAssertEqual(manager.state, .reconnecting)
    }

    func testConnectionManagerSendsHeartbeatEnvelopeAfterHandshakeSuccess() async throws {
        let socket = StubWebSocketClient()
        let manager = ConnectionManager(socket: socket, heartbeatInterval: 0.01, timeoutInterval: 0.05)

        try await manager.connect(host: "127.0.0.1", port: 9876)
        socket.pushIncomingEnvelope(makeAgentInfoEnvelope())

        try await Task.sleep(nanoseconds: 25_000_000)

        XCTAssertTrue(socket.sentData.dropFirst().contains(where: { data in
            guard let envelope = try? ProtobufCodec.decode(data) else {
                return false
            }
            if case .heartbeat = envelope.payload {
                return true
            }
            return false
        }))
    }

    func testConnectionManagerReconnectsAfterInboundTimeout() async throws {
        let socket = StubWebSocketClient()
        let manager = ConnectionManager(socket: socket, heartbeatInterval: 0.05, timeoutInterval: 0.02)

        try await manager.connect(host: "127.0.0.1", port: 9876)
        socket.pushIncomingEnvelope(makeAgentInfoEnvelope())

        try await Task.sleep(nanoseconds: 30_000_000)

        XCTAssertEqual(manager.state, .reconnecting)
    }
}

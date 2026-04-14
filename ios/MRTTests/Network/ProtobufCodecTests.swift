@testable import MRT
import XCTest

final class ProtobufCodecTests: XCTestCase {
    func testEnvelopeRoundTrip() throws {
        var envelope = Mrt_Envelope()
        envelope.protocolVersion = 1
        envelope.requestID = "req-1"
        envelope.timestampMs = 42

        let data = try ProtobufCodec.encode(envelope)
        let decoded = try ProtobufCodec.decode(data)

        XCTAssertEqual(decoded.requestID, "req-1")
        XCTAssertEqual(decoded.timestampMs, 42)
    }

    func testLengthPrefixMatchesRemainingPayloadLength() throws {
        var envelope = Mrt_Envelope()
        envelope.requestID = "req-2"

        let data = try ProtobufCodec.encode(envelope)
        let length = data.prefix(4).reduce(0) { ($0 << 8) | UInt32($1) }

        XCTAssertEqual(Int(length), data.count - 4)
    }

    func testDecodeRejectsFramesShorterThanLengthPrefix() {
        XCTAssertThrowsError(try ProtobufCodec.decode(Data([0x00, 0x00, 0x00])))
    }
}

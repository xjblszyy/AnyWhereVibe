import Foundation
import SwiftProtobuf

enum ProtobufCodecError: Error, Equatable {
    case frameTooShort
    case invalidLengthPrefix(expected: Int, actual: Int)
}

enum ProtobufCodec {
    static func encode(_ envelope: Mrt_Envelope) throws -> Data {
        let payload = try envelope.serializedData()
        var length = UInt32(payload.count).bigEndian
        var framed = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
        framed.append(payload)
        return framed
    }

    static func decode(_ data: Data) throws -> Mrt_Envelope {
        guard data.count >= 4 else {
            throw ProtobufCodecError.frameTooShort
        }

        let declaredLength = data.prefix(4).reduce(0) { ($0 << 8) | UInt32($1) }
        let payload = data.dropFirst(4)

        guard payload.count == Int(declaredLength) else {
            throw ProtobufCodecError.invalidLengthPrefix(
                expected: Int(declaredLength),
                actual: payload.count
            )
        }

        return try Mrt_Envelope(serializedBytes: payload)
    }
}

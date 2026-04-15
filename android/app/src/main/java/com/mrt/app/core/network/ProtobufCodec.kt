package com.mrt.app.core.network

import mrt.Mrt
import java.nio.ByteBuffer
import java.nio.ByteOrder

sealed class ProtobufCodecError(message: String) : IllegalArgumentException(message) {
    data object FrameTooShort : ProtobufCodecError("Frame shorter than 4-byte length prefix")
    data class InvalidLengthPrefix(val expected: Int, val actual: Int) :
        ProtobufCodecError("Invalid length prefix. Expected $expected bytes, got $actual")
}

object ProtobufCodec {
    fun encode(envelope: Mrt.Envelope): ByteArray {
        val payload = envelope.toByteArray()
        return ByteBuffer
            .allocate(4 + payload.size)
            .order(ByteOrder.BIG_ENDIAN)
            .putInt(payload.size)
            .put(payload)
            .array()
    }

    fun decode(data: ByteArray): Mrt.Envelope {
        if (data.size < 4) {
            throw ProtobufCodecError.FrameTooShort
        }

        val payloadLength = ByteBuffer
            .wrap(data, 0, 4)
            .order(ByteOrder.BIG_ENDIAN)
            .int
        val payload = data.copyOfRange(4, data.size)

        if (payload.size != payloadLength) {
            throw ProtobufCodecError.InvalidLengthPrefix(
                expected = payloadLength,
                actual = payload.size,
            )
        }

        return Mrt.Envelope.parseFrom(payload)
    }
}

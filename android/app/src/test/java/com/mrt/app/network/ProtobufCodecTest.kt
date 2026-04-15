package com.mrt.app.network

import com.mrt.app.core.network.ProtobufCodec
import com.mrt.app.core.network.ProtobufCodecError
import mrt.Mrt
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class ProtobufCodecTest {
    @Test
    fun envelopeRoundTripPreservesMetadata() {
        val envelope = Mrt.Envelope.newBuilder()
            .setProtocolVersion(1)
            .setRequestId("req-1")
            .setTimestampMs(42)
            .build()

        val encoded = ProtobufCodec.encode(envelope)
        val decoded = ProtobufCodec.decode(encoded)

        assertEquals("req-1", decoded.requestId)
        assertEquals(42L, decoded.timestampMs)
    }

    @Test
    fun lengthPrefixMatchesRemainingPayloadLength() {
        val envelope = Mrt.Envelope.newBuilder()
            .setRequestId("req-2")
            .build()

        val encoded = ProtobufCodec.encode(envelope)
        val length = ((encoded[0].toInt() and 0xFF) shl 24) or
            ((encoded[1].toInt() and 0xFF) shl 16) or
            ((encoded[2].toInt() and 0xFF) shl 8) or
            (encoded[3].toInt() and 0xFF)

        assertEquals(encoded.size - 4, length)
    }

    @Test
    fun decodeRejectsFramesShorterThanLengthPrefix() {
        val error = assertThrows(ProtobufCodecError::class.java) {
            ProtobufCodec.decode(byteArrayOf(0x00, 0x00, 0x00))
        }

        assertEquals(ProtobufCodecError.FrameTooShort, error)
    }

    @Test
    fun decodeRejectsFramesWithInvalidLengthPrefix() {
        val error = assertThrows(ProtobufCodecError::class.java) {
            ProtobufCodec.decode(byteArrayOf(0x00, 0x00, 0x00, 0x05, 0x01, 0x02, 0x03))
        }

        assertEquals(ProtobufCodecError.InvalidLengthPrefix(expected = 5, actual = 3), error)
    }
}

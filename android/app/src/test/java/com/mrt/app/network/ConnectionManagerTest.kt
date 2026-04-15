package com.mrt.app.network

import com.mrt.app.core.network.ConnectionManager
import com.mrt.app.core.network.ConnectionManagerError
import com.mrt.app.core.network.ConnectionState
import com.mrt.app.core.network.ProtobufCodec
import com.mrt.app.core.network.WebSocketClientProtocol
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import mrt.Mrt
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.util.concurrent.atomic.AtomicInteger

class ConnectionManagerTest {
    @Test
    fun connectionManagerConnectsToSocketUrlSendsHandshakeAndWaitsForAgentInfo() = runBlocking {
        val socket = StubWebSocketClient()
        val manager = ConnectionManager(
            socket = socket,
            heartbeatIntervalMillis = 15_000,
            timeoutIntervalMillis = 45_000,
        )

        manager.connect(host = "127.0.0.1", port = 9876)

        assertEquals("ws://127.0.0.1:9876/", socket.connectedUrl)
        assertEquals(ConnectionState.CONNECTING, manager.state.value)
        assertEquals(1, socket.sentFrames.size)

        val handshake = ProtobufCodec.decode(socket.sentFrames.first())
        assertEquals(Mrt.Envelope.PayloadCase.HANDSHAKE, handshake.payloadCase)

        socket.pushIncomingEnvelope(makeAgentInfoEnvelope())

        assertEquals(ConnectionState.CONNECTED, manager.state.value)
    }

    @Test
    fun connectionManagerReconnectsOnSocketClose() = runBlocking {
        val socket = StubWebSocketClient()
        val manager = ConnectionManager(
            socket = socket,
            heartbeatIntervalMillis = 100,
            timeoutIntervalMillis = 45_000,
            reconnectRetryDelayMillis = 10,
        )

        manager.connect(host = "127.0.0.1", port = 9876)
        socket.pushIncomingEnvelope(makeAgentInfoEnvelope())

        socket.simulateClose()
        delay(30)

        assertEquals(2, socket.connectCalls.size)
        assertEquals("ws://127.0.0.1:9876/", socket.connectCalls.last())
        assertEquals(ConnectionState.RECONNECTING, manager.state.value)
        assertEquals(2, socket.sentFrames.size)
        assertEquals(
            Mrt.Envelope.PayloadCase.HANDSHAKE,
            ProtobufCodec.decode(socket.sentFrames.last()).payloadCase,
        )
    }

    @Test
    fun connectionManagerSendsHeartbeatEnvelopeAfterHandshakeSuccess() = runBlocking {
        val socket = StubWebSocketClient()
        val manager = ConnectionManager(
            socket = socket,
            heartbeatIntervalMillis = 10,
            timeoutIntervalMillis = 50,
        )

        manager.connect(host = "127.0.0.1", port = 9876)
        socket.pushIncomingEnvelope(makeAgentInfoEnvelope())
        delay(30)

        assertTrue(socket.sentFrames.drop(1).any { frame ->
            ProtobufCodec.decode(frame).payloadCase == Mrt.Envelope.PayloadCase.HEARTBEAT
        })
    }

    @Test
    fun connectionManagerReconnectsAfterInboundTimeout() = runBlocking {
        val socket = StubWebSocketClient()
        val manager = ConnectionManager(
            socket = socket,
            heartbeatIntervalMillis = 50,
            timeoutIntervalMillis = 20,
            reconnectRetryDelayMillis = 10,
        )

        manager.connect(host = "127.0.0.1", port = 9876)
        socket.pushIncomingEnvelope(makeAgentInfoEnvelope())
        delay(60)

        assertTrue(socket.connectCalls.size >= 2)
        assertEquals(ConnectionState.RECONNECTING, manager.state.value)
        assertEquals(
            Mrt.Envelope.PayloadCase.HANDSHAKE,
            ProtobufCodec.decode(socket.sentFrames.last()).payloadCase,
        )
    }

    @Test
    fun connectionManagerRejectsPromptSendBeforeHandshakeSuccess() = runBlocking {
        val socket = StubWebSocketClient()
        val manager = ConnectionManager(socket = socket)

        manager.connect(host = "127.0.0.1", port = 9876)

        try {
            manager.sendPrompt(prompt = "hello", sessionId = "session-1")
            fail("expected not connected error")
        } catch (error: ConnectionManagerError) {
            assertEquals(ConnectionManagerError.NotConnected, error)
        }

        assertEquals(1, socket.sentFrames.size)
        assertEquals(
            Mrt.Envelope.PayloadCase.HANDSHAKE,
            ProtobufCodec.decode(socket.sentFrames.first()).payloadCase,
        )
    }

    @Test
    fun connectionManagerPublishesInboundDispatcherState() = runBlocking {
        val socket = StubWebSocketClient()
        val manager = ConnectionManager(socket = socket)

        manager.connect(host = "127.0.0.1", port = 9876)
        socket.pushIncomingEnvelope(makeAgentInfoEnvelope())
        socket.pushIncomingEnvelope(makeCodexOutputEnvelope(content = "Hello ", complete = false))
        socket.pushIncomingEnvelope(makeCodexOutputEnvelope(content = "world", complete = true))
        socket.pushIncomingEnvelope(makeApprovalRequestEnvelope())
        socket.pushIncomingEnvelope(makeSessionListEnvelope())

        assertEquals("Hello world", manager.messages.value.last().content)
        assertTrue(manager.messages.value.last().isComplete)
        assertEquals("approval-1", manager.pendingApproval.value?.approvalId)
        assertEquals(listOf("session-1"), manager.sessions.value.map { it.id })
    }

    @Test
    fun connectionManagerRegistersPhoneInManagedMode() = runBlocking {
        val socket = StubWebSocketClient()
        val manager = ConnectionManager(socket = socket)

        manager.connectManaged(
            nodeUrl = "ws://relay.example.com/ws",
            authToken = "mrt_ak_example1234567890",
            deviceId = "pixel-1",
            displayName = "Pixel 1",
        )

        assertEquals("ws://relay.example.com/ws", socket.connectedUrl)
        val registerEnvelope = ProtobufCodec.decode(socket.sentFrames.first())
        assertEquals(Mrt.Envelope.PayloadCase.DEVICE_REGISTER, registerEnvelope.payloadCase)

        socket.pushIncomingEnvelope(makeDeviceRegisterAckEnvelope(success = true))

        assertEquals(ConnectionState.CONNECTED, manager.state.value)
    }

    @Test
    fun connectionManagerPublishesManagedDeviceList() = runBlocking {
        val socket = StubWebSocketClient()
        val manager = ConnectionManager(socket = socket)

        manager.connectManaged(
            nodeUrl = "ws://relay.example.com/ws",
            authToken = "mrt_ak_example1234567890",
            deviceId = "pixel-1",
            displayName = "Pixel 1",
        )
        socket.pushIncomingEnvelope(makeDeviceRegisterAckEnvelope(success = true))

        manager.requestDeviceList()

        assertEquals(
            Mrt.Envelope.PayloadCase.DEVICE_LIST_REQUEST,
            ProtobufCodec.decode(socket.sentFrames.last()).payloadCase,
        )

        socket.pushIncomingEnvelope(makeDeviceListResponseEnvelope())

        assertEquals(listOf("agent-1"), manager.devices.value.map { it.deviceId })
    }

    @Test
    fun connectionManagerConnectToDeviceSendsHandshakeAndTransitionsToAgentConnected() = runBlocking {
        val socket = StubWebSocketClient()
        val manager = ConnectionManager(socket = socket)

        manager.connectManaged(
            nodeUrl = "ws://relay.example.com/ws",
            authToken = "mrt_ak_example1234567890",
            deviceId = "pixel-1",
            displayName = "Pixel 1",
        )
        socket.pushIncomingEnvelope(makeDeviceRegisterAckEnvelope(success = true))

        manager.connectToDevice(targetDeviceId = "agent-1")

        assertEquals(
            Mrt.Envelope.PayloadCase.CONNECT_TO_DEVICE,
            ProtobufCodec.decode(socket.sentFrames.last()).payloadCase,
        )

        socket.pushIncomingEnvelope(makeConnectToDeviceAckEnvelope(success = true))
        delay(10)

        assertEquals(
            Mrt.Envelope.PayloadCase.HANDSHAKE,
            ProtobufCodec.decode(socket.sentFrames.last()).payloadCase,
        )

        socket.pushIncomingEnvelope(makeAgentInfoEnvelope())

        assertEquals(ConnectionState.CONNECTED, manager.state.value)
    }

    @Test
    fun connectionManagerAutoConnectsToSavedManagedTargetAfterRegisterAck() = runBlocking {
        val socket = StubWebSocketClient()
        val manager = ConnectionManager(socket = socket)

        manager.connectManaged(
            nodeUrl = "ws://relay.example.com/ws",
            authToken = "mrt_ak_example1234567890",
            deviceId = "pixel-1",
            displayName = "Pixel 1",
            targetDeviceId = "agent-1",
        )

        socket.pushIncomingEnvelope(makeDeviceRegisterAckEnvelope(success = true))
        delay(10)

        assertEquals(
            Mrt.Envelope.PayloadCase.CONNECT_TO_DEVICE,
            ProtobufCodec.decode(socket.sentFrames.last()).payloadCase,
        )
    }
}

internal class StubWebSocketClient : WebSocketClientProtocol {
    var connectedUrl: String? = null
    val connectCalls = mutableListOf<String>()
    val sentFrames = mutableListOf<ByteArray>()
    var connectDelayMillis: Long? = null
    var connectErrors: ArrayDeque<Throwable> = ArrayDeque()
    var disconnectCallCount = AtomicInteger(0)

    override var onReceive: ((ByteArray) -> Unit)? = null
    override var onClose: (() -> Unit)? = null

    override suspend fun connect(url: String) {
        connectedUrl = url
        connectCalls += url
        if (connectErrors.isNotEmpty()) {
            throw connectErrors.removeFirst()
        }
        connectDelayMillis?.let {
            connectDelayMillis = null
            delay(it)
        }
    }

    override suspend fun send(data: ByteArray) {
        sentFrames += data
    }

    override fun disconnect() {
        disconnectCallCount.incrementAndGet()
        onClose?.invoke()
    }

    fun pushIncomingEnvelope(envelope: Mrt.Envelope) {
        onReceive?.invoke(ProtobufCodec.encode(envelope))
    }

    fun simulateClose() {
        onClose?.invoke()
    }
}

internal fun makeAgentInfoEnvelope(): Mrt.Envelope =
    Mrt.Envelope.newBuilder()
        .setEvent(
            Mrt.AgentEvent.newBuilder()
                .setAgentInfo(
                    Mrt.AgentInfo.newBuilder()
                        .setAgentVersion("0.1.0")
                        .setAdapterType("mock")
                        .setHostname("test-mac")
                        .setOs("Android")
                        .build(),
                )
                .build(),
        )
        .build()

internal fun makeCodexOutputEnvelope(content: String, complete: Boolean): Mrt.Envelope =
    Mrt.Envelope.newBuilder()
        .setEvent(
            Mrt.AgentEvent.newBuilder()
                .setCodexOutput(
                    Mrt.CodexOutput.newBuilder()
                        .setSessionId("session-1")
                        .setContent(content)
                        .setIsComplete(complete)
                        .build(),
                )
                .build(),
        )
        .build()

internal fun makeApprovalRequestEnvelope(): Mrt.Envelope =
    Mrt.Envelope.newBuilder()
        .setEvent(
            Mrt.AgentEvent.newBuilder()
                .setApprovalRequest(
                    Mrt.ApprovalRequest.newBuilder()
                        .setApprovalId("approval-1")
                        .setSessionId("session-1")
                        .setDescription("Write to file src/main.rs")
                        .setCommand("echo hi")
                        .build(),
                )
                .build(),
        )
        .build()

internal fun makeSessionListEnvelope(): Mrt.Envelope =
    Mrt.Envelope.newBuilder()
        .setEvent(
            Mrt.AgentEvent.newBuilder()
                .setSessionList(
                    Mrt.SessionListUpdate.newBuilder()
                        .addSessions(
                            Mrt.SessionInfo.newBuilder()
                                .setSessionId("session-1")
                                .setName("Main")
                                .setWorkingDir("/tmp/project")
                                .build(),
                        )
                        .build(),
                )
                .build(),
        )
        .build()

internal fun makeDeviceRegisterAckEnvelope(success: Boolean): Mrt.Envelope =
    Mrt.Envelope.newBuilder()
        .setDeviceRegisterAck(
            Mrt.DeviceRegisterAck.newBuilder()
                .setSuccess(success)
                .setMessage(if (success) "registered" else "invalid auth token")
                .build(),
        )
        .build()

internal fun makeDeviceListResponseEnvelope(): Mrt.Envelope =
    Mrt.Envelope.newBuilder()
        .setDeviceListResponse(
            Mrt.DeviceListResponse.newBuilder()
                .addDevices(
                    Mrt.DeviceInfo.newBuilder()
                        .setDeviceId("agent-1")
                        .setDeviceType(Mrt.DeviceType.AGENT)
                        .setDisplayName("Office Mac")
                        .setIsOnline(true)
                        .build(),
                )
                .build(),
        )
        .build()

internal fun makeConnectToDeviceAckEnvelope(success: Boolean): Mrt.Envelope =
    Mrt.Envelope.newBuilder()
        .setConnectToDeviceAck(
            Mrt.ConnectToDeviceAck.newBuilder()
                .setSuccess(success)
                .setMessage(if (success) "connected" else "device unavailable")
                .setConnectionType(Mrt.ConnectionType.RELAY)
                .build(),
        )
        .build()

internal fun makeErrorEnvelope(
    code: String = "CODEX_UNAVAILABLE",
    message: String = "Codex unavailable",
    fatal: Boolean = false,
): Mrt.Envelope =
    Mrt.Envelope.newBuilder()
        .setEvent(
            Mrt.AgentEvent.newBuilder()
                .setError(
                    Mrt.ErrorEvent.newBuilder()
                        .setCode(code)
                        .setMessage(message)
                        .setFatal(fatal)
                        .build(),
                )
                .build(),
        )
        .build()

internal fun makeRunningStatusEnvelope(): Mrt.Envelope =
    Mrt.Envelope.newBuilder()
        .setEvent(
            Mrt.AgentEvent.newBuilder()
                .setStatusUpdate(
                    Mrt.TaskStatusUpdate.newBuilder()
                        .setSessionId("session-1")
                        .setStatus(Mrt.TaskStatus.RUNNING)
                        .build(),
                )
                .build(),
        )
        .build()

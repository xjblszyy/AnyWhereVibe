package com.mrt.app.core.network

import com.mrt.app.core.models.ChatMessage
import com.mrt.app.core.models.SessionModel
import com.mrt.app.core.storage.ConnectionMode
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import mrt.Mrt
import java.util.UUID

enum class ConnectionState {
    DISCONNECTED,
    CONNECTING,
    CONNECTED,
    LOADING,
    SHOWING_APPROVAL,
    RECONNECTING,
}

sealed class ConnectionManagerError(message: String) : IllegalStateException(message) {
    data object NotConnected : ConnectionManagerError("Connection has not completed the handshake")
    data object InvalidEndpoint : ConnectionManagerError("Invalid websocket endpoint")
}

interface ConnectionManaging {
    val state: StateFlow<ConnectionState>
    val messages: StateFlow<List<ChatMessage>>
    val pendingApproval: StateFlow<Mrt.ApprovalRequest?>
    val sessions: StateFlow<List<SessionModel>>

    suspend fun connect(host: String, port: Int)
    fun disconnect()
    suspend fun sendPrompt(prompt: String, sessionId: String)
    suspend fun respondToApproval(approvalId: String, approved: Boolean)
    suspend fun cancelTask(sessionId: String)
    suspend fun switchSession(sessionId: String)
    suspend fun createSession(name: String, workingDirectory: String)
    suspend fun closeSession(sessionId: String)
}

class ConnectionManager(
    private val socket: WebSocketClientProtocol = WebSocketClient(),
    private val heartbeatIntervalMillis: Long = 15_000,
    private val timeoutIntervalMillis: Long = 45_000,
    private val reconnectRetryDelayMillis: Long = 500,
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.IO),
    private val requestIdProvider: () -> String = { UUID.randomUUID().toString() },
    private val deviceIdProvider: () -> String = { UUID.randomUUID().toString() },
    private val nowMs: () -> Long = { System.currentTimeMillis() },
) : ConnectionManaging {
    private val dispatcher = MessageDispatcher()
    private val lock = Any()

    private val _state = MutableStateFlow(ConnectionState.DISCONNECTED)
    override val state: StateFlow<ConnectionState> = _state.asStateFlow()

    private val _messages = MutableStateFlow<List<ChatMessage>>(emptyList())
    override val messages: StateFlow<List<ChatMessage>> = _messages.asStateFlow()

    private val _pendingApproval = MutableStateFlow<Mrt.ApprovalRequest?>(null)
    override val pendingApproval: StateFlow<Mrt.ApprovalRequest?> = _pendingApproval.asStateFlow()

    private val _sessions = MutableStateFlow<List<SessionModel>>(emptyList())
    override val sessions: StateFlow<List<SessionModel>> = _sessions.asStateFlow()

    private val _devices = MutableStateFlow<List<Mrt.DeviceInfo>>(emptyList())
    val devices: StateFlow<List<Mrt.DeviceInfo>> = _devices.asStateFlow()

    private var heartbeatJob: Job? = null
    private var timeoutJob: Job? = null
    private var reconnectJob: Job? = null
    private var handshakeSucceeded = false
    private var nodeRegistrationSucceeded = false
    private var lastInboundMessageAt: Long? = null
    private var endpointUrl: String? = null
    private var connectionAttemptId: String = UUID.randomUUID().toString()
    private var connectionMode: ConnectionMode = ConnectionMode.DIRECT
    private var nodeRegistration: NodeRegistration? = null
    private var pendingTargetDeviceId: String? = null

    private data class NodeRegistration(
        val authToken: String,
        val deviceId: String,
        val displayName: String,
    )

    override suspend fun connect(host: String, port: Int) {
        val trimmedHost = host.trim()
        if (trimmedHost.isEmpty() || trimmedHost.contains("://")) {
            throw ConnectionManagerError.InvalidEndpoint
        }

        val url = "ws://$trimmedHost:$port/"
        val attemptId = UUID.randomUUID().toString()
        synchronized(lock) {
            connectionMode = ConnectionMode.DIRECT
            nodeRegistration = null
            endpointUrl = url
            connectionAttemptId = attemptId
            reconnectJob?.cancel()
            reconnectJob = null
        }

        try {
            establishConnection(url = url, connectionState = ConnectionState.CONNECTING, attemptId = attemptId)
        } catch (error: CancellationException) {
            throw error
        } catch (_: Throwable) {
            transitionToReconnecting()
        }
    }

    suspend fun connectManaged(
        nodeUrl: String,
        authToken: String,
        deviceId: String,
        displayName: String,
        targetDeviceId: String? = null,
    ) {
        val trimmedNodeUrl = nodeUrl.trim()
        if (!trimmedNodeUrl.startsWith("ws://") && !trimmedNodeUrl.startsWith("wss://")) {
            throw ConnectionManagerError.InvalidEndpoint
        }

        val registration = NodeRegistration(
            authToken = authToken.trim(),
            deviceId = deviceId.trim(),
            displayName = displayName.trim(),
        )
        val attemptId = UUID.randomUUID().toString()
        synchronized(lock) {
            connectionMode = ConnectionMode.MANAGED
            nodeRegistration = registration
            pendingTargetDeviceId = targetDeviceId
            endpointUrl = trimmedNodeUrl
            connectionAttemptId = attemptId
            reconnectJob?.cancel()
            reconnectJob = null
        }

        try {
            establishManagedConnection(
                url = trimmedNodeUrl,
                registration = registration,
                connectionState = ConnectionState.CONNECTING,
                attemptId = attemptId,
            )
        } catch (error: CancellationException) {
            throw error
        } catch (_: Throwable) {
            transitionToReconnecting()
        }
    }

    override fun disconnect() {
        synchronized(lock) {
            endpointUrl = null
            nodeRegistration = null
            connectionAttemptId = UUID.randomUUID().toString()
            reconnectJob?.cancel()
            reconnectJob = null
            _state.value = ConnectionState.DISCONNECTED
        }
        teardownSocket()
    }

    override suspend fun sendPrompt(prompt: String, sessionId: String) {
        ensureConnected()
        val command = Mrt.AgentCommand.newBuilder()
            .setSendPrompt(
                Mrt.SendPrompt.newBuilder()
                    .setSessionId(sessionId)
                    .setPrompt(prompt)
                    .build(),
            )
            .build()

        _state.value = ConnectionState.LOADING
        sendEnvelope(makeEnvelope { setCommand(command) })
    }

    override suspend fun respondToApproval(approvalId: String, approved: Boolean) {
        ensureConnected()
        val command = Mrt.AgentCommand.newBuilder()
            .setApprovalResponse(
                Mrt.ApprovalResponse.newBuilder()
                    .setApprovalId(approvalId)
                    .setApproved(approved)
                    .build(),
            )
            .build()

        synchronized(lock) {
            dispatcher.clearPendingApproval()
            syncDispatcherOutputsLocked()
        }
        sendEnvelope(makeEnvelope { setCommand(command) })
    }

    override suspend fun cancelTask(sessionId: String) {
        ensureConnected()
        val command = Mrt.AgentCommand.newBuilder()
            .setCancelTask(
                Mrt.CancelTask.newBuilder()
                    .setSessionId(sessionId)
                    .build(),
            )
            .build()

        sendEnvelope(makeEnvelope { setCommand(command) })
    }

    override suspend fun switchSession(sessionId: String) {
        ensureConnected()
        val control = Mrt.SessionControl.newBuilder()
            .setSwitchTo(
                Mrt.SwitchSession.newBuilder()
                    .setSessionId(sessionId)
                    .build(),
            )
            .build()

        sendEnvelope(makeEnvelope { setSession(control) })
    }

    override suspend fun createSession(name: String, workingDirectory: String) {
        ensureConnected()
        val control = Mrt.SessionControl.newBuilder()
            .setCreate(
                Mrt.CreateSession.newBuilder()
                    .setName(name)
                    .setWorkingDir(workingDirectory)
                    .build(),
            )
            .build()

        sendEnvelope(makeEnvelope { setSession(control) })
    }

    override suspend fun closeSession(sessionId: String) {
        ensureConnected()
        val control = Mrt.SessionControl.newBuilder()
            .setClose(
                Mrt.CloseSession.newBuilder()
                    .setSessionId(sessionId)
                    .build(),
            )
            .build()

        sendEnvelope(makeEnvelope { setSession(control) })
    }

    suspend fun requestDeviceList() {
        ensureManagedRegistered()
        sendEnvelope(
            makeEnvelope {
                setDeviceListRequest(Mrt.DeviceListRequest.getDefaultInstance())
            },
        )
    }

    suspend fun connectToDevice(targetDeviceId: String) {
        ensureManagedRegistered()
        sendEnvelope(
            makeEnvelope {
                setConnectToDevice(
                    Mrt.ConnectToDevice.newBuilder()
                        .setTargetDeviceId(targetDeviceId)
                        .build(),
                )
            },
        )
    }

    private suspend fun establishConnection(url: String, connectionState: ConnectionState, attemptId: String) {
        ensureActiveAttempt(attemptId)
        teardownSocket()
        ensureActiveAttempt(attemptId)
        configureSocketCallbacks(attemptId)
        _state.value = connectionState
        ensureActiveAttempt(attemptId)
        socket.connect(url)
        ensureActiveAttempt(attemptId)
        sendEnvelope(makeHandshakeEnvelope())
        startHandshakeTimeoutLoop(attemptId)
    }

    private suspend fun establishManagedConnection(
        url: String,
        registration: NodeRegistration,
        connectionState: ConnectionState,
        attemptId: String,
    ) {
        ensureActiveAttempt(attemptId)
        teardownSocket()
        ensureActiveAttempt(attemptId)
        configureSocketCallbacks(attemptId)
        _state.value = connectionState
        ensureActiveAttempt(attemptId)
        socket.connect(url)
        ensureActiveAttempt(attemptId)
        sendEnvelope(
            makeEnvelope {
                setDeviceRegister(
                    Mrt.DeviceRegister.newBuilder()
                        .setDeviceId(registration.deviceId)
                        .setAuthToken(registration.authToken)
                        .setDeviceType(Mrt.DeviceType.PHONE)
                        .setDisplayName(registration.displayName)
                        .setAgentVersion("1.0.0")
                        .build(),
                )
            },
        )
    }

    private fun configureSocketCallbacks(attemptId: String) {
        socket.onReceive = { data ->
            handleIncomingData(data = data, attemptId = attemptId)
        }
        socket.onClose = {
            handleSocketClose(attemptId)
        }
    }

    private fun handleIncomingData(data: ByteArray, attemptId: String) {
        val envelope = try {
            ProtobufCodec.decode(data)
        } catch (_: Throwable) {
            return
        }

        var shouldReconnect = false
        var shouldSendManagedHandshake = false
        synchronized(lock) {
            if (attemptId != connectionAttemptId) {
                return
            }

            lastInboundMessageAt = nowMs()

            when (envelope.payloadCase) {
                Mrt.Envelope.PayloadCase.EVENT -> {
                    when (envelope.event.evtCase) {
                        Mrt.AgentEvent.EvtCase.AGENT_INFO -> {
                            if (!handshakeSucceeded) {
                                handshakeSucceeded = true
                                _state.value = ConnectionState.CONNECTED
                                lastInboundMessageAt = nowMs()
                                startHeartbeatLoop()
                                startInboundTimeoutLoop(attemptId)
                            }
                        }
                        Mrt.AgentEvent.EvtCase.APPROVAL_REQUEST -> _state.value = ConnectionState.SHOWING_APPROVAL
                        Mrt.AgentEvent.EvtCase.STATUS_UPDATE -> {
                            _state.value = when (envelope.event.statusUpdate.status) {
                                Mrt.TaskStatus.RUNNING -> ConnectionState.LOADING
                                Mrt.TaskStatus.WAITING_APPROVAL -> ConnectionState.SHOWING_APPROVAL
                                Mrt.TaskStatus.COMPLETED,
                                Mrt.TaskStatus.CANCELLED,
                                Mrt.TaskStatus.ERROR,
                                Mrt.TaskStatus.IDLE,
                                Mrt.TaskStatus.TASK_STATUS_UNSPECIFIED,
                                Mrt.TaskStatus.UNRECOGNIZED,
                                null,
                                -> ConnectionState.CONNECTED
                            }
                        }
                        Mrt.AgentEvent.EvtCase.ERROR -> {
                            if (envelope.event.error.fatal) {
                                shouldReconnect = true
                            }
                        }
                        Mrt.AgentEvent.EvtCase.CODEX_OUTPUT,
                        Mrt.AgentEvent.EvtCase.SESSION_LIST,
                        Mrt.AgentEvent.EvtCase.EVT_NOT_SET,
                        -> Unit
                        null -> Unit
                    }
                }
                Mrt.Envelope.PayloadCase.DEVICE_REGISTER_ACK -> {
                    nodeRegistrationSucceeded = envelope.deviceRegisterAck.success
                    val pendingTarget = pendingTargetDeviceId
                    _state.value = if (envelope.deviceRegisterAck.success && pendingTarget != null) {
                        ConnectionState.CONNECTING
                    } else if (envelope.deviceRegisterAck.success) {
                        ConnectionState.CONNECTED
                    } else {
                        ConnectionState.DISCONNECTED
                    }
                    if (envelope.deviceRegisterAck.success && pendingTarget != null) {
                        scope.launch {
                            try {
                                connectToDevice(pendingTarget)
                            } catch (_: Throwable) {
                                transitionToReconnecting()
                            }
                        }
                    }
                }
                Mrt.Envelope.PayloadCase.DEVICE_LIST_RESPONSE -> {
                    _devices.value = envelope.deviceListResponse.devicesList
                }
                Mrt.Envelope.PayloadCase.CONNECT_TO_DEVICE_ACK -> {
                    if (envelope.connectToDeviceAck.success) {
                        _state.value = ConnectionState.CONNECTING
                        shouldSendManagedHandshake = true
                        startHandshakeTimeoutLoop(attemptId)
                    } else {
                        _state.value = ConnectionState.CONNECTED
                    }
                }
                else -> return
            }

            dispatcher.apply(envelope)
            syncDispatcherOutputsLocked()
        }

        if (shouldSendManagedHandshake) {
            scope.launch {
                try {
                    sendEnvelope(makeHandshakeEnvelope())
                } catch (_: Throwable) {
                    transitionToReconnecting()
                }
            }
        }

        if (shouldReconnect) {
            transitionToReconnecting()
        }
    }

    private fun handleSocketClose(attemptId: String) {
        synchronized(lock) {
            if (attemptId != connectionAttemptId) {
                return
            }
        }
        transitionToReconnecting()
    }

    private fun startHeartbeatLoop() {
        heartbeatJob?.cancel()
        heartbeatJob = scope.launch {
            while (true) {
                delay(heartbeatIntervalMillis)
                val shouldSend = synchronized(lock) { handshakeSucceeded }
                if (!shouldSend) {
                    return@launch
                }

                try {
                    sendEnvelope(
                        makeEnvelope {
                            setHeartbeat(Mrt.Heartbeat.getDefaultInstance())
                        },
                    )
                } catch (_: Throwable) {
                    transitionToReconnecting()
                    return@launch
                }
            }
        }
    }

    private fun startHandshakeTimeoutLoop(attemptId: String) {
        timeoutJob?.cancel()
        timeoutJob = scope.launch {
            val pollInterval = timeoutIntervalMillis.coerceAtLeast(1) / 4L
            val startedAt = nowMs()

            while (true) {
                delay(pollInterval.coerceAtLeast(1))
                val shouldReconnect = synchronized(lock) {
                    attemptId == connectionAttemptId &&
                        !handshakeSucceeded &&
                        (nowMs() - startedAt) > timeoutIntervalMillis
                }
                if (shouldReconnect) {
                    transitionToReconnecting()
                    return@launch
                }
            }
        }
    }

    private fun startInboundTimeoutLoop(attemptId: String) {
        timeoutJob?.cancel()
        timeoutJob = scope.launch {
            val pollInterval = timeoutIntervalMillis.coerceAtLeast(1) / 4L
            while (true) {
                delay(pollInterval.coerceAtLeast(1))
                val shouldReconnect = synchronized(lock) {
                    val lastInbound = lastInboundMessageAt
                    attemptId == connectionAttemptId &&
                        lastInbound != null &&
                        (nowMs() - lastInbound) > timeoutIntervalMillis
                }
                if (shouldReconnect) {
                    transitionToReconnecting()
                    return@launch
                }
            }
        }
    }

    private suspend fun sendEnvelope(envelope: Mrt.Envelope) {
        socket.send(ProtobufCodec.encode(envelope))
    }

    private fun makeHandshakeEnvelope(): Mrt.Envelope =
        makeEnvelope {
            setHandshake(
                Mrt.Handshake.newBuilder()
                    .setProtocolVersion(1)
                    .setClientType(Mrt.ClientType.PHONE_ANDROID)
                    .setClientVersion("1.0.0")
                    .setDeviceId(deviceIdProvider())
                    .build(),
            )
        }

    private fun makeEnvelope(configure: Mrt.Envelope.Builder.() -> Unit): Mrt.Envelope =
        Mrt.Envelope.newBuilder()
            .setProtocolVersion(1)
            .setRequestId(requestIdProvider())
            .setTimestampMs(nowMs())
            .apply(configure)
            .build()

    private fun transitionToReconnecting() {
        val reconnectUrl: String
        val attemptId: String
        synchronized(lock) {
            if (_state.value == ConnectionState.DISCONNECTED) {
                return
            }

            _state.value = ConnectionState.RECONNECTING
            teardownSocket()
            if (reconnectJob != null || endpointUrl == null) {
                return
            }

            reconnectUrl = endpointUrl ?: return
            attemptId = UUID.randomUUID().toString()
            connectionAttemptId = attemptId
            reconnectJob = scope.launch {
                var shouldRetry = false
                try {
                    ensureActiveAttempt(attemptId)
                    when (connectionMode) {
                        ConnectionMode.DIRECT -> establishConnection(
                            url = reconnectUrl,
                            connectionState = ConnectionState.RECONNECTING,
                            attemptId = attemptId,
                        )
                        ConnectionMode.MANAGED -> {
                            val registration = synchronized(lock) { nodeRegistration } ?: return@launch
                            establishManagedConnection(
                                url = reconnectUrl,
                                registration = registration,
                                connectionState = ConnectionState.RECONNECTING,
                                attemptId = attemptId,
                            )
                        }
                    }
                } catch (_: CancellationException) {
                } catch (_: Throwable) {
                    shouldRetry = true
                } finally {
                    synchronized(lock) {
                        reconnectJob = null
                    }
                    if (shouldRetry) {
                        scheduleReconnectRetry()
                    }
                }
            }
        }
    }

    private fun scheduleReconnectRetry() {
        scope.launch {
            delay(reconnectRetryDelayMillis)
            transitionToReconnecting()
        }
    }

    private fun teardownSocket() {
        heartbeatJob?.cancel()
        timeoutJob?.cancel()
        heartbeatJob = null
        timeoutJob = null
        handshakeSucceeded = false
        nodeRegistrationSucceeded = false
        lastInboundMessageAt = null

        socket.onReceive = null
        socket.onClose = null
        socket.disconnect()
    }

    private fun syncDispatcherOutputsLocked() {
        val dispatcherState = dispatcher.state
        if (dispatcherState != ConnectionState.DISCONNECTED || _state.value == ConnectionState.DISCONNECTED) {
            _state.value = dispatcherState
        }
        _messages.value = dispatcher.messages
        _pendingApproval.value = dispatcher.pendingApproval
        _sessions.value = dispatcher.sessions
    }

    private fun ensureConnected() {
        val connected = synchronized(lock) { handshakeSucceeded }
        if (!connected) {
            throw ConnectionManagerError.NotConnected
        }
    }

    private fun ensureManagedRegistered() {
        val registered = synchronized(lock) { nodeRegistrationSucceeded }
        if (!registered) {
            throw ConnectionManagerError.NotConnected
        }
    }

    private fun ensureActiveAttempt(attemptId: String) {
        if (attemptId != synchronized(lock) { connectionAttemptId }) {
            throw CancellationException("stale connection attempt")
        }
    }
}

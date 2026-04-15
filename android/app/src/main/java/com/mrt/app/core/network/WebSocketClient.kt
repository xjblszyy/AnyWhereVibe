package com.mrt.app.core.network

import kotlinx.coroutines.suspendCancellableCoroutine
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.ByteString
import okio.ByteString.Companion.toByteString
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

sealed class WebSocketClientError(message: String) : IllegalStateException(message) {
    data object NotConnected : WebSocketClientError("WebSocket is not connected")
}

interface WebSocketClientProtocol {
    var onReceive: ((ByteArray) -> Unit)?
    var onClose: (() -> Unit)?

    suspend fun connect(url: String)
    suspend fun send(data: ByteArray)
    fun disconnect()
}

class WebSocketClient(
    private val client: OkHttpClient = OkHttpClient(),
) : WebSocketClientProtocol {
    override var onReceive: ((ByteArray) -> Unit)? = null
    override var onClose: (() -> Unit)? = null

    private var socket: WebSocket? = null
    private var hasClosed = false

    override suspend fun connect(url: String) {
        shutdown(notifyClose = false)
        hasClosed = false

        suspendCancellableCoroutine { continuation ->
            var resumed = false
            val request = Request.Builder()
                .url(url)
                .build()
            val listener = object : WebSocketListener() {
                override fun onOpen(webSocket: WebSocket, response: Response) {
                    socket = webSocket
                    if (!resumed) {
                        resumed = true
                        continuation.resume(Unit)
                    }
                }

                override fun onMessage(webSocket: WebSocket, bytes: ByteString) {
                    onReceive?.invoke(bytes.toByteArray())
                }

                override fun onMessage(webSocket: WebSocket, text: String) {
                    onReceive?.invoke(text.encodeToByteArray())
                }

                override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                    webSocket.close(code, reason)
                    notifyClosedIfNeeded()
                }

                override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                    notifyClosedIfNeeded()
                }

                override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                    if (!resumed) {
                        resumed = true
                        continuation.resumeWithException(t)
                    } else {
                        notifyClosedIfNeeded()
                    }
                }
            }
            val webSocket = client.newWebSocket(request, listener)
            socket = webSocket

            continuation.invokeOnCancellation {
                if (socket === webSocket) {
                    webSocket.cancel()
                    socket = null
                }
            }
        }
    }

    override suspend fun send(data: ByteArray) {
        val webSocket = socket ?: throw WebSocketClientError.NotConnected
        if (!webSocket.send(data.toByteString())) {
            throw WebSocketClientError.NotConnected
        }
    }

    override fun disconnect() {
        shutdown(notifyClose = true)
    }

    private fun shutdown(notifyClose: Boolean) {
        socket?.close(1001, null)
        socket = null
        if (notifyClose) {
            notifyClosedIfNeeded()
        }
    }

    private fun notifyClosedIfNeeded() {
        if (hasClosed) {
            return
        }
        hasClosed = true
        onClose?.invoke()
    }
}

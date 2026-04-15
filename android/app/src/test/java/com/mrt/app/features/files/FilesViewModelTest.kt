package com.mrt.app.features.files

import com.mrt.app.core.models.ChatMessage
import com.mrt.app.core.models.FileViewerState
import com.mrt.app.core.models.FilesUnavailableReason
import com.mrt.app.core.models.FilesViewState
import com.mrt.app.core.models.SessionModel
import com.mrt.app.core.network.ConnectionManaging
import com.mrt.app.core.network.ConnectionState
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import mrt.Mrt
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class FilesViewModelTest {
    @Test
    fun filesViewModelLoadsRootDirectory() = runTest {
        val connection = FakeFilesConnectionManager()
        val viewModel = FilesViewModel(connectionManager = connection, scope = backgroundScope)

        viewModel.updateContext(ConnectionState.CONNECTED, "session-1")
        viewModel.setVisible(true)
        advanceUntilIdle()
        val requestId = connection.listRequests.last().requestId

        connection.emitDirListing(
            sessionId = "session-1",
            requestId = requestId,
            entries = listOf("Sources" to true, "notes.txt" to false),
        )
        advanceUntilIdle()

        val state = viewModel.state as FilesViewState.DirectoryReady
        assertEquals("", state.path)
        assertEquals(listOf("Sources", "notes.txt"), state.entries.map { it.name })
    }

    @Test
    fun filesViewModelOpensTextFileAndSavesChanges() = runTest {
        val connection = FakeFilesConnectionManager()
        val viewModel = FilesViewModel(connectionManager = connection, scope = backgroundScope)

        viewModel.updateContext(ConnectionState.CONNECTED, "session-1")
        viewModel.setVisible(true)
        advanceUntilIdle()
        connection.emitDirListing("session-1", connection.listRequests.last().requestId, listOf("notes.txt" to false))
        advanceUntilIdle()

        val entry = (viewModel.state as FilesViewState.DirectoryReady).entries.first()
        viewModel.enter(entry)
        advanceUntilIdle()
        connection.emitFileContent("session-1", connection.readRequests.last().requestId, "notes.txt", "hello\n")
        advanceUntilIdle()

        viewModel.updateEditor("updated\n")
        viewModel.saveCurrentFile()
        advanceUntilIdle()
        connection.emitWriteAck("session-1", connection.writeRequests.last().requestId, "notes.txt")
        advanceUntilIdle()
        connection.emitDirListing("session-1", connection.listRequests.last().requestId, listOf("notes.txt" to false))
        advanceUntilIdle()

        val state = viewModel.state as FilesViewState.DirectoryReady
        val viewer = state.viewer as FileViewerState.Editable
        assertEquals("updated\n", viewer.content)
        assertEquals("Saved notes.txt.", state.mutationMessage)
    }

    @Test
    fun filesViewModelHandlesCreateRenameDelete() = runTest {
        val connection = FakeFilesConnectionManager()
        val viewModel = FilesViewModel(connectionManager = connection, scope = backgroundScope)

        viewModel.updateContext(ConnectionState.CONNECTED, "session-1")
        viewModel.setVisible(true)
        advanceUntilIdle()
        connection.emitDirListing("session-1", connection.listRequests.last().requestId, emptyList())
        advanceUntilIdle()

        viewModel.draftName = "new.txt"
        viewModel.createFile()
        advanceUntilIdle()
        connection.emitMutationAck("session-1", connection.createFileRequests.last().requestId, "new.txt", "created")
        advanceUntilIdle()
        connection.emitDirListing("session-1", connection.listRequests.last().requestId, listOf("new.txt" to false))
        advanceUntilIdle()

        val entry = (viewModel.state as FilesViewState.DirectoryReady).entries.first()
        viewModel.enter(entry)
        advanceUntilIdle()
        connection.emitFileContent("session-1", connection.readRequests.last().requestId, "new.txt", "")
        advanceUntilIdle()
        viewModel.renameDraft = "renamed.txt"
        viewModel.renameSelected()
        advanceUntilIdle()
        connection.emitMutationAck("session-1", connection.renameRequests.last().requestId, "renamed.txt", "renamed")
        advanceUntilIdle()
        connection.emitDirListing("session-1", connection.listRequests.last().requestId, listOf("renamed.txt" to false))
        advanceUntilIdle()
        viewModel.deleteSelected()
        advanceUntilIdle()
        connection.emitMutationAck("session-1", connection.deleteRequests.last().requestId, "renamed.txt", "deleted")
        advanceUntilIdle()
        connection.emitDirListing("session-1", connection.listRequests.last().requestId, emptyList())
        advanceUntilIdle()

        val state = viewModel.state as FilesViewState.DirectoryReady
        assertTrue(state.entries.isEmpty())
        assertEquals("Deleted", state.mutationMessage)
    }

    @Test
    fun filesViewModelShowsUnsupportedStateForBinaryFile() = runTest {
        val connection = FakeFilesConnectionManager()
        val viewModel = FilesViewModel(connectionManager = connection, scope = backgroundScope)

        viewModel.updateContext(ConnectionState.CONNECTED, "session-1")
        viewModel.setVisible(true)
        advanceUntilIdle()
        connection.emitDirListing("session-1", connection.listRequests.last().requestId, listOf("binary.bin" to false))
        advanceUntilIdle()
        viewModel.enter((viewModel.state as FilesViewState.DirectoryReady).entries.first())
        advanceUntilIdle()
        connection.emitFileError("session-1", connection.readRequests.last().requestId, "FILE_UNSUPPORTED_TYPE", "binary file")
        advanceUntilIdle()

        val state = viewModel.state as FilesViewState.DirectoryReady
        assertEquals(FileViewerState.ReadOnly("binary.bin", "binary file"), state.viewer)
    }

    @Test
    fun filesViewModelShowsUnavailableWithoutConnectedSession() = runTest {
        val connection = FakeFilesConnectionManager()
        val viewModel = FilesViewModel(connectionManager = connection, scope = backgroundScope)

        viewModel.setVisible(true)
        advanceUntilIdle()
        assertEquals(FilesViewState.Unavailable(FilesUnavailableReason.DISCONNECTED), viewModel.state)
    }
}

private class FakeFilesConnectionManager : ConnectionManaging {
    private val _state = MutableStateFlow(ConnectionState.DISCONNECTED)
    override val state: StateFlow<ConnectionState> = _state.asStateFlow()

    private val _messages = MutableStateFlow<List<ChatMessage>>(emptyList())
    override val messages: StateFlow<List<ChatMessage>> = _messages.asStateFlow()

    private val _pendingApproval = MutableStateFlow<Mrt.ApprovalRequest?>(null)
    override val pendingApproval: StateFlow<Mrt.ApprovalRequest?> = _pendingApproval.asStateFlow()

    private val _sessions = MutableStateFlow<List<SessionModel>>(emptyList())
    override val sessions: StateFlow<List<SessionModel>> = _sessions.asStateFlow()

    private val _fileEnvelopes = MutableStateFlow<Mrt.Envelope?>(null)
    override val fileEnvelopes: StateFlow<Mrt.Envelope?> = _fileEnvelopes.asStateFlow()

    private val _gitEnvelopes = MutableStateFlow<Mrt.Envelope?>(null)
    override val gitEnvelopes: StateFlow<Mrt.Envelope?> = _gitEnvelopes.asStateFlow()

    val listRequests = mutableListOf<Request>()
    val readRequests = mutableListOf<Request>()
    val writeRequests = mutableListOf<Request>()
    val createFileRequests = mutableListOf<Request>()
    val createDirRequests = mutableListOf<Request>()
    val deleteRequests = mutableListOf<Request>()
    val renameRequests = mutableListOf<RenameRequest>()
    private var counter = 0

    override suspend fun connect(host: String, port: Int) = Unit
    override fun disconnect() = Unit
    override suspend fun sendPrompt(prompt: String, sessionId: String) = Unit
    override suspend fun respondToApproval(approvalId: String, approved: Boolean) = Unit
    override suspend fun cancelTask(sessionId: String) = Unit
    override suspend fun switchSession(sessionId: String) = Unit
    override suspend fun createSession(name: String, workingDirectory: String) = Unit
    override suspend fun closeSession(sessionId: String) = Unit
    override suspend fun requestGitStatus(sessionId: String): String = "git-status"
    override suspend fun requestGitDiff(sessionId: String, path: String): String = "git-diff"

    override suspend fun listDirectory(sessionId: String, path: String): String {
        val id = nextId("list")
        listRequests += Request(sessionId, path, id)
        _state.value = ConnectionState.CONNECTED
        return id
    }

    override suspend fun readFile(sessionId: String, path: String): String {
        val id = nextId("read")
        readRequests += Request(sessionId, path, id)
        return id
    }

    override suspend fun writeFile(sessionId: String, path: String, content: ByteArray): String {
        val id = nextId("write")
        writeRequests += Request(sessionId, path, id)
        return id
    }

    override suspend fun createFile(sessionId: String, path: String): String {
        val id = nextId("create-file")
        createFileRequests += Request(sessionId, path, id)
        return id
    }

    override suspend fun createDirectory(sessionId: String, path: String): String {
        val id = nextId("create-dir")
        createDirRequests += Request(sessionId, path, id)
        return id
    }

    override suspend fun deletePath(sessionId: String, path: String, recursive: Boolean): String {
        val id = nextId("delete")
        deleteRequests += Request(sessionId, path, id)
        return id
    }

    override suspend fun renamePath(sessionId: String, fromPath: String, toPath: String): String {
        val id = nextId("rename")
        renameRequests += RenameRequest(sessionId, fromPath, toPath, id)
        return id
    }

    fun emitDirListing(sessionId: String, requestId: String, entries: List<Pair<String, Boolean>>) {
        _fileEnvelopes.value = Mrt.Envelope.newBuilder()
            .setRequestId(requestId)
            .setFileResult(
                Mrt.FileResult.newBuilder()
                    .setSessionId(sessionId)
                    .setDirListing(
                        Mrt.DirListing.newBuilder()
                            .addAllEntries(
                                entries.map { (name, isDir) ->
                                    Mrt.FileEntry.newBuilder()
                                        .setName(name)
                                        .setPath(name)
                                        .setIsDir(isDir)
                                        .setSize(0)
                                        .setModifiedMs(1)
                                        .build()
                                },
                            )
                            .build(),
                    )
                    .build(),
            )
            .build()
    }

    fun emitFileContent(sessionId: String, requestId: String, path: String, content: String) {
        _fileEnvelopes.value = Mrt.Envelope.newBuilder()
            .setRequestId(requestId)
            .setFileResult(
                Mrt.FileResult.newBuilder()
                    .setSessionId(sessionId)
                    .setFileContent(
                        Mrt.FileContent.newBuilder()
                            .setPath(path)
                            .setContent(com.google.protobuf.ByteString.copyFromUtf8(content))
                            .setMimeType("text/plain")
                            .build(),
                    )
                    .build(),
            )
            .build()
    }

    fun emitWriteAck(sessionId: String, requestId: String, path: String) {
        _fileEnvelopes.value = Mrt.Envelope.newBuilder()
            .setRequestId(requestId)
            .setFileResult(
                Mrt.FileResult.newBuilder()
                    .setSessionId(sessionId)
                    .setWriteAck(Mrt.FileWriteAck.newBuilder().setPath(path).setSuccess(true).build())
                    .build(),
            )
            .build()
    }

    fun emitMutationAck(sessionId: String, requestId: String, path: String, message: String) {
        _fileEnvelopes.value = Mrt.Envelope.newBuilder()
            .setRequestId(requestId)
            .setFileResult(
                Mrt.FileResult.newBuilder()
                    .setSessionId(sessionId)
                    .setMutationAck(
                        Mrt.FileMutationAck.newBuilder()
                            .setPath(path)
                            .setSuccess(true)
                            .setMessage(message)
                            .build(),
                    )
                    .build(),
            )
            .build()
    }

    fun emitFileError(sessionId: String, requestId: String, code: String, message: String) {
        _fileEnvelopes.value = Mrt.Envelope.newBuilder()
            .setRequestId(requestId)
            .setFileResult(
                Mrt.FileResult.newBuilder()
                    .setSessionId(sessionId)
                    .setError(
                        Mrt.ErrorEvent.newBuilder()
                            .setCode(code)
                            .setMessage(message)
                            .setFatal(false)
                            .build(),
                    )
                    .build(),
            )
            .build()
    }

    private fun nextId(prefix: String): String {
        counter += 1
        return "$prefix-$counter"
    }

    data class Request(val sessionId: String, val path: String, val requestId: String)
    data class RenameRequest(val sessionId: String, val fromPath: String, val toPath: String, val requestId: String)
}

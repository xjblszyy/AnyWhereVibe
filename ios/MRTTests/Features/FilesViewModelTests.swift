@testable import MRT
import XCTest

final class FilesViewModelTests: XCTestCase {
    @MainActor
    func testFilesViewModelLoadsRootDirectory() async throws {
        let connection = StubConnectionManager()
        let viewModel = FilesViewModel(connectionManager: connection)

        viewModel.updateContext(connectionState: .connected, activeSessionID: "session-1")
        viewModel.setVisible(true)
        try? await Task.sleep(nanoseconds: 20_000_000)

        let requestID = try XCTUnwrap(connection.listedDirectories.last?.requestID)
        connection.emitDirListing(sessionID: "session-1", requestID: requestID, entries: [
            ("Sources", "Sources", true),
            ("notes.txt", "notes.txt", false),
        ])
        try? await Task.sleep(nanoseconds: 20_000_000)

        guard case let .directoryReady(path, entries, _, _) = viewModel.state else {
            return XCTFail("expected directory ready")
        }
        XCTAssertEqual(path, "")
        XCTAssertEqual(entries.map(\.path), ["Sources", "notes.txt"])
    }

    @MainActor
    func testFilesViewModelOpensTextFileAndSavesChanges() async throws {
        let connection = StubConnectionManager()
        let viewModel = FilesViewModel(connectionManager: connection)

        viewModel.updateContext(connectionState: .connected, activeSessionID: "session-1")
        viewModel.setVisible(true)
        try? await Task.sleep(nanoseconds: 20_000_000)
        let listRequestID = try XCTUnwrap(connection.listedDirectories.last?.requestID)
        connection.emitDirListing(sessionID: "session-1", requestID: listRequestID, entries: [
            ("notes.txt", "notes.txt", false),
        ])
        try? await Task.sleep(nanoseconds: 20_000_000)

        let entry = try XCTUnwrap(viewModel.directoryEntries.first)
        viewModel.enter(entry)
        try? await Task.sleep(nanoseconds: 20_000_000)
        let readRequestID = try XCTUnwrap(connection.readFiles.last?.requestID)
        connection.emitFileContent(sessionID: "session-1", requestID: readRequestID, path: "notes.txt", content: "hello\n")
        try? await Task.sleep(nanoseconds: 20_000_000)

        viewModel.updateEditor("updated\n")
        let listCountBeforeSave = connection.listedDirectories.count
        viewModel.saveCurrentFile()
        try? await Task.sleep(nanoseconds: 20_000_000)
        let writeRequestID = try XCTUnwrap(connection.wroteFiles.last?.requestID)
        connection.emitFileWriteAck(sessionID: "session-1", requestID: writeRequestID, path: "notes.txt")
        try await waitUntil { connection.listedDirectories.count > listCountBeforeSave }
        let refreshRequestID = try XCTUnwrap(connection.listedDirectories.last?.requestID)
        connection.emitDirListing(sessionID: "session-1", requestID: refreshRequestID, entries: [
            ("notes.txt", "notes.txt", false),
        ])
        try? await Task.sleep(nanoseconds: 20_000_000)

        guard case let .directoryReady(_, _, .editable(_, content, isSaving, _), mutationMessage) = viewModel.state else {
            return XCTFail("expected editable state")
        }
        XCTAssertEqual(content, "updated\n")
        XCTAssertFalse(isSaving)
        XCTAssertEqual(mutationMessage, "Saved notes.txt.")
    }

    @MainActor
    func testFilesViewModelHandlesCreateRenameDelete() async throws {
        let connection = StubConnectionManager()
        let viewModel = FilesViewModel(connectionManager: connection)

        viewModel.updateContext(connectionState: .connected, activeSessionID: "session-1")
        viewModel.setVisible(true)
        try? await Task.sleep(nanoseconds: 20_000_000)
        let rootRequestID = try XCTUnwrap(connection.listedDirectories.last?.requestID)
        connection.emitDirListing(sessionID: "session-1", requestID: rootRequestID, entries: [])
        try? await Task.sleep(nanoseconds: 20_000_000)

        viewModel.draftName = "new.txt"
        let createListCount = connection.listedDirectories.count
        viewModel.createFile()
        try? await Task.sleep(nanoseconds: 20_000_000)
        let createRequestID = try XCTUnwrap(connection.createdFiles.last?.requestID)
        connection.emitFileMutationAck(sessionID: "session-1", requestID: createRequestID, path: "new.txt", message: "created")
        try await waitUntil { connection.listedDirectories.count > createListCount }
        let refreshAfterCreate = try XCTUnwrap(connection.listedDirectories.last?.requestID)
        connection.emitDirListing(sessionID: "session-1", requestID: refreshAfterCreate, entries: [("new.txt", "new.txt", false)])
        try? await Task.sleep(nanoseconds: 20_000_000)

        let entry = try XCTUnwrap(viewModel.directoryEntries.first)
        viewModel.enter(entry)
        try? await Task.sleep(nanoseconds: 20_000_000)
        let readRequestID = try XCTUnwrap(connection.readFiles.last?.requestID)
        connection.emitFileContent(sessionID: "session-1", requestID: readRequestID, path: "new.txt", content: "")
        try? await Task.sleep(nanoseconds: 20_000_000)

        viewModel.renameDraft = "renamed.txt"
        let renameListCount = connection.listedDirectories.count
        viewModel.renameSelected()
        try? await Task.sleep(nanoseconds: 20_000_000)
        let renameRequestID = try XCTUnwrap(connection.renamedPaths.last?.requestID)
        connection.emitFileMutationAck(sessionID: "session-1", requestID: renameRequestID, path: "renamed.txt", message: "renamed")
        try await waitUntil { connection.listedDirectories.count > renameListCount }
        let refreshAfterRename = try XCTUnwrap(connection.listedDirectories.last?.requestID)
        connection.emitDirListing(sessionID: "session-1", requestID: refreshAfterRename, entries: [("renamed.txt", "renamed.txt", false)])
        try? await Task.sleep(nanoseconds: 20_000_000)

        let deleteListCount = connection.listedDirectories.count
        viewModel.deleteSelected()
        try? await Task.sleep(nanoseconds: 20_000_000)
        let deleteRequestID = try XCTUnwrap(connection.deletedPaths.last?.requestID)
        connection.emitFileMutationAck(sessionID: "session-1", requestID: deleteRequestID, path: "renamed.txt", message: "deleted")
        try await waitUntil { connection.listedDirectories.count > deleteListCount }
        let refreshAfterDelete = try XCTUnwrap(connection.listedDirectories.last?.requestID)
        connection.emitDirListing(sessionID: "session-1", requestID: refreshAfterDelete, entries: [])
        try? await Task.sleep(nanoseconds: 20_000_000)

        guard case let .directoryReady(_, entries, _, mutationMessage) = viewModel.state else {
            return XCTFail("expected directory ready")
        }
        XCTAssertTrue(entries.isEmpty)
        XCTAssertEqual(mutationMessage, "Deleted")
    }

    @MainActor
    func testFilesViewModelShowsUnsupportedStateForBinaryFile() async throws {
        let connection = StubConnectionManager()
        let viewModel = FilesViewModel(connectionManager: connection)

        viewModel.updateContext(connectionState: .connected, activeSessionID: "session-1")
        viewModel.setVisible(true)
        try? await Task.sleep(nanoseconds: 20_000_000)
        let listRequestID = try XCTUnwrap(connection.listedDirectories.last?.requestID)
        connection.emitDirListing(sessionID: "session-1", requestID: listRequestID, entries: [("binary.bin", "binary.bin", false)])
        try? await Task.sleep(nanoseconds: 20_000_000)

        let entry = try XCTUnwrap(viewModel.directoryEntries.first)
        viewModel.enter(entry)
        try? await Task.sleep(nanoseconds: 20_000_000)
        let readRequestID = try XCTUnwrap(connection.readFiles.last?.requestID)
        connection.emitFileError(sessionID: "session-1", requestID: readRequestID, code: "FILE_UNSUPPORTED_TYPE", message: "binary file")
        try? await Task.sleep(nanoseconds: 20_000_000)

        guard case let .directoryReady(_, _, .readOnly(path, message), _) = viewModel.state else {
            return XCTFail("expected read only state")
        }
        XCTAssertEqual(path, "binary.bin")
        XCTAssertEqual(message, "binary file")
    }
}

private extension FilesViewModel {
    var directoryEntries: [FileEntryModel] {
        if case let .directoryReady(_, entries, _, _) = state {
            return entries
        }
        return []
    }
}

private func waitUntil(
    timeoutNanoseconds: UInt64 = 200_000_000,
    condition: () -> Bool
) async throws {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
    while !condition() {
        if DispatchTime.now().uptimeNanoseconds > deadline {
            throw XCTSkip("timed out waiting for async state")
        }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
}

import Foundation

protocol WebSocketClientProtocol: AnyObject {
    var onReceive: ((Data) -> Void)? { get set }
    var onClose: (() -> Void)? { get set }

    func connect(url: URL) async throws
    func send(_ data: Data) async throws
    func disconnect()
}

final class WebSocketClient: NSObject, WebSocketClientProtocol {
    var onReceive: ((Data) -> Void)?
    var onClose: (() -> Void)?

    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private var activeTaskID = UUID()
    private var hasClosed = false

    func connect(url: URL) async throws {
        shutdown(notifyClose: false)

        hasClosed = false
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        let task = session.webSocketTask(with: url)
        let taskID = UUID()
        self.session = session
        self.task = task
        self.activeTaskID = taskID
        task.resume()
        receiveNextMessage(for: task, taskID: taskID)
    }

    func send(_ data: Data) async throws {
        guard let task else { return }
        try await task.send(.data(data))
    }

    func disconnect() {
        shutdown(notifyClose: true)
    }

    private func shutdown(notifyClose: Bool) {
        task?.cancel(with: .goingAway, reason: nil)
        session?.invalidateAndCancel()
        task = nil
        session = nil
        if notifyClose {
            notifyClosedIfNeeded()
        }
    }

    private func receiveNextMessage(for task: URLSessionWebSocketTask, taskID: UUID) {
        task.receive { [weak self] result in
            guard let self else { return }
            guard self.task === task, self.activeTaskID == taskID else { return }

            switch result {
            case .success(.data(let data)):
                self.onReceive?(data)
                self.receiveNextMessage(for: task, taskID: taskID)
            case .success(.string(let text)):
                if let data = text.data(using: .utf8) {
                    self.onReceive?(data)
                }
                self.receiveNextMessage(for: task, taskID: taskID)
            case .success:
                self.receiveNextMessage(for: task, taskID: taskID)
            case .failure:
                self.notifyClosedIfNeeded()
            }
        }
    }

    private func notifyClosedIfNeeded() {
        guard !hasClosed else { return }
        hasClosed = true
        onClose?()
    }
}

extension WebSocketClient: URLSessionWebSocketDelegate {
    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        guard task === webSocketTask else { return }
        notifyClosedIfNeeded()
    }
}

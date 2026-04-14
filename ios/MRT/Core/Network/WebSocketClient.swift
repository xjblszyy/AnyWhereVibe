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
    private var hasClosed = false

    func connect(url: URL) async throws {
        disconnect()

        hasClosed = false
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        let task = session.webSocketTask(with: url)
        self.session = session
        self.task = task
        task.resume()
        receiveNextMessage()
    }

    func send(_ data: Data) async throws {
        guard let task else { return }
        try await task.send(.data(data))
    }

    func disconnect() {
        task?.cancel(with: .goingAway, reason: nil)
        session?.invalidateAndCancel()
        task = nil
        session = nil
        notifyClosedIfNeeded()
    }

    private func receiveNextMessage() {
        task?.receive { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(.data(let data)):
                self.onReceive?(data)
                self.receiveNextMessage()
            case .success(.string(let text)):
                if let data = text.data(using: .utf8) {
                    self.onReceive?(data)
                }
                self.receiveNextMessage()
            case .success:
                self.receiveNextMessage()
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
        notifyClosedIfNeeded()
    }
}

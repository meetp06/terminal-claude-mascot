// Thin WebSocket client over URLSessionWebSocketTask. Raw JSON in, raw JSON out.
// All callbacks are delivered on the main queue so the UI/overlay can consume
// them directly. Auto-reconnects with a small backoff.
import Foundation

final class WSClient: NSObject {
    private var task: URLSessionWebSocketTask?
    private var session: URLSession!
    private var url: URL?
    private var shouldRun = false
    private var backoff: TimeInterval = 1

    /// Called with each decoded JSON object received from the sidecar.
    var onMessage: (([String: Any]) -> Void)?
    /// Called when the connection opens (true) or drops (false).
    var onConnected: ((Bool) -> Void)?

    override init() {
        super.init()
        session = URLSession(configuration: .default)
    }

    func connect(urlString: String) {
        guard let u = URL(string: urlString) else { return }
        url = u
        shouldRun = true
        openSocket()
    }

    func stop() {
        shouldRun = false
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    private func openSocket() {
        guard shouldRun, let u = url else { return }
        let t = session.webSocketTask(with: u)
        task = t
        t.resume()
        DispatchQueue.main.async { [weak self] in self?.onConnected?(true) }
        backoff = 1
        receiveLoop()
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure:
                DispatchQueue.main.async { self.onConnected?(false) }
                self.scheduleReconnect()
            case .success(let message):
                switch message {
                case .string(let text):
                    self.dispatch(text)
                case .data(let data):
                    if let s = String(data: data, encoding: .utf8) { self.dispatch(s) }
                @unknown default:
                    break
                }
                self.receiveLoop()
            }
        }
    }

    private func dispatch(_ text: String) {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }
        DispatchQueue.main.async { [weak self] in self?.onMessage?(obj) }
    }

    private func scheduleReconnect() {
        guard shouldRun else { return }
        let delay = backoff
        backoff = min(backoff * 2, 15)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.openSocket()
        }
    }

    func send(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let text = String(data: data, encoding: .utf8) else { return }
        task?.send(.string(text)) { _ in }
    }
}

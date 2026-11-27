// The one-shot web server that catches Google's redirect after consent.
//
// Google sends the browser back to http://127.0.0.1:<port> with the code in
// the query. This listens on a port the system picks, answers the one request,
// and hands back what arrived. It is bound to the loopback address, so nothing
// off this machine can reach it, and it stops as soon as the answer is in.

import Foundation
import Network

// Unchecked, because the only mutable state is the continuation and the
// finished flag, and both are guarded by the lock below.
final class LoopbackListener: @unchecked Sendable {
    private let listener: NWListener
    private let port: UInt16
    private var waiting: CheckedContinuation<[String: String], Error>?
    private var finished = false
    private let lock = NSLock()

    var redirectURI: String { "http://127.0.0.1:\(port)" }

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)

        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready.signal() }
            if case .failed = state { ready.signal() }
        }
        listener.start(queue: .global())
        // A local listener comes up at once; the wait is only so the port is known.
        _ = ready.wait(timeout: .now() + 5)

        guard let assigned = listener.port?.rawValue, assigned != 0 else {
            listener.cancel()
            throw GoogleError("could not listen for Google's answer")
        }
        port = assigned
    }

    /// Waits for the browser to come back. Gives up after five minutes, so a
    /// sign-in that is never finished does not wait for ever.
    func wait() async throws -> [String: String] {
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        return try await withThrowingTaskGroup(of: [String: String].self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    self.waiting = continuation
                }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(300))
                throw GoogleError("sign-in timed out")
            }
            let answer = try await group.next()!
            group.cancelAll()
            return answer
        }
    }

    func stop() {
        listener.cancel()
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: .global())
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }
            let answer = Self.queryItems(in: request)
            let page = """
            HTTP/1.1 200 OK\r
            Content-Type: text/html; charset=utf-8\r
            Connection: close\r
            \r
            <html><body style="font-family: -apple-system; padding: 3rem">
            <h2>Crossroads is signed in.</h2><p>You can close this tab.</p>
            </body></html>
            """
            connection.send(content: Data(page.utf8), completion: .contentProcessed { _ in
                connection.cancel()
            })
            self.finish(with: answer)
        }
    }

    /// Resumes the caller once, however many requests the browser makes.
    private func finish(with answer: [String: String]) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished, let waiting else { return }
        finished = true
        self.waiting = nil
        waiting.resume(returning: answer)
    }

    /// The query from the request line, which looks like "GET /?code=... HTTP/1.1".
    private static func queryItems(in request: String) -> [String: String] {
        guard let line = request.split(separator: "\r\n").first else { return [:] }
        let parts = line.split(separator: " ")
        guard parts.count >= 2,
              let url = URLComponents(string: "http://127.0.0.1\(parts[1])")
        else { return [:] }
        return Dictionary(
            (url.queryItems ?? []).compactMap { item in item.value.map { (item.name, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
    }
}

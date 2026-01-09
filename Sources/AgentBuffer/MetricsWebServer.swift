import Foundation
import Network

final class MetricsWebServer {
    private let queue = DispatchQueue(label: "AgentBuffer.MetricsWebServer")
    private var listener: NWListener?
    private let engine = MetricsEngine()
    private let defaultPort: UInt16 = 48900
    private let maxAttempts = 5
    private var activeConnections: [ObjectIdentifier: ConnectionContext] = [:]
    private var currentPort: UInt16?
    private let host = "127.0.0.1"

    func start() {
        queue.async { [weak self] in
            self?.startListener(port: self?.defaultPort ?? 48900, attempts: self?.maxAttempts ?? 0)
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.listener?.cancel()
            self?.listener = nil
            self?.currentPort = nil
            cleanupDiscoveryFile()
        }
    }

    func metricsURL() -> URL? {
        let port = queue.sync { currentPort }
        if let port {
            return URL(string: "http://\(host):\(port)/")
        }
        guard let fallbackPort = readDiscoveryPort() else {
            return nil
        }
        return URL(string: "http://\(host):\(fallbackPort)/")
    }

    private func startListener(port: UInt16, attempts: Int) {
        do {
            let parameters = NWParameters.tcp
            let host = NWEndpoint.Host("127.0.0.1")
            guard let portEndpoint = NWEndpoint.Port(rawValue: port) else {
                return
            }
            parameters.requiredLocalEndpoint = .hostPort(host: host, port: portEndpoint)
            let listener = try NWListener(using: parameters)
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.listener = listener
                    let actualPort = listener.port?.rawValue ?? port
                    self?.currentPort = UInt16(actualPort)
                    writeDiscoveryFile(port: UInt16(actualPort))
                    if Settings.devModeEnabled {
                        NSLog("[AgentBuffer] Metrics server listening on http://127.0.0.1:%d", actualPort)
                    }
                case .failed(let error):
                    if case let NWError.posix(posix) = error, posix == .EADDRINUSE, attempts > 0 {
                        listener.cancel()
                        self?.startListener(port: port + 1, attempts: attempts - 1)
                    } else {
                        if Settings.devModeEnabled {
                            NSLog("[AgentBuffer] Metrics server failed: %@", String(describing: error))
                        }
                        listener.cancel()
                    }
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection: connection)
            }
            listener.start(queue: queue)
        } catch {
            if attempts > 0 {
                startListener(port: port + 1, attempts: attempts - 1)
            } else if Settings.devModeEnabled {
                NSLog("[AgentBuffer] Metrics server failed to start: %@", error.localizedDescription)
            }
        }
    }

    private func handle(connection: NWConnection) {
        let key = ObjectIdentifier(connection)
        let context = ConnectionContext(connection: connection, engine: engine) { [weak self] in
            self?.activeConnections.removeValue(forKey: key)
        }
        activeConnections[key] = context
        connection.start(queue: queue)
        context.receive()
    }
}

private final class ConnectionContext {
    private var buffer = Data()
    private let connection: NWConnection
    private let engine: MetricsEngine
    private let onClose: () -> Void
    private var didFinish = false

    init(connection: NWConnection, engine: MetricsEngine, onClose: @escaping () -> Void) {
        self.connection = connection
        self.engine = engine
        self.onClose = onClose
    }

    func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data {
                self.buffer.append(data)
            }
            if let request = self.parseRequest() {
                self.respond(to: request)
                return
            }
            if isComplete || error != nil {
                self.connection.cancel()
                self.finish()
                return
            }
            self.receive()
        }
    }

    private func parseRequest() -> HttpRequest? {
        guard let range = buffer.range(of: Data("\r\n\r\n".utf8)) else {
            return nil
        }
        let headerData = buffer.subdata(in: 0..<range.lowerBound)
        guard let headerString = String(data: headerData, encoding: .utf8) else {
            return nil
        }
        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first, !requestLine.isEmpty else {
            return nil
        }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            return nil
        }
        let method = String(parts[0])
        let path = String(parts[1])
        return HttpRequest(method: method, path: path)
    }

    private func respond(to request: HttpRequest) {
        guard request.method.uppercased() == "GET" else {
            sendResponse(status: 405, contentType: "text/plain; charset=utf-8", body: "Method not allowed")
            return
        }
        if request.path.hasPrefix("/api/") {
            handleApi(request)
            return
        }
        serveStatic(request)
    }

    private func handleApi(_ request: HttpRequest) {
        let components = URLComponents(string: "http://localhost\(request.path)")
        let path = components?.path ?? ""
        switch path {
        case "/api/summary":
            let summary = engine.summary()
            sendJson(summary)
        case "/api/timeseries":
            let window = components?.queryItems?.first(where: { $0.name == "window" })?.value ?? "24h"
            let step = Int(components?.queryItems?.first(where: { $0.name == "step" })?.value ?? "60") ?? 60
            let response = engine.timeseries(windowKey: window, stepSeconds: step)
            sendJson(response)
        case "/api/health":
            let payload = ["ok": true, "time": isoString(Date())] as [String : Any]
            sendJsonDictionary(payload)
        default:
            sendResponse(status: 404, contentType: "text/plain; charset=utf-8", body: "Not found")
        }
    }

    private func serveStatic(_ request: HttpRequest) {
        var path = request.path
        if path == "/" {
            path = "/index.html"
        }
        if path.contains("..") {
            sendResponse(status: 404, contentType: "text/plain; charset=utf-8", body: "Not found")
            return
        }
        let resourcePath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let resourceURL: URL?
        if let ext = resourcePath.split(separator: ".").last, !ext.isEmpty {
            let name = resourcePath.dropLast(ext.count + 1)
            resourceURL = Bundle.module.url(
                forResource: String(name),
                withExtension: String(ext),
                subdirectory: "metrics-web"
            ) ?? Bundle.module.url(
                forResource: String(name),
                withExtension: String(ext)
            )
        } else {
            resourceURL = Bundle.module.url(
                forResource: resourcePath,
                withExtension: nil,
                subdirectory: "metrics-web"
            ) ?? Bundle.module.url(forResource: resourcePath, withExtension: nil)
        }
        guard let resourceURL, let data = try? Data(contentsOf: resourceURL) else {
            sendResponse(status: 404, contentType: "text/plain; charset=utf-8", body: "Not found")
            return
        }
        let contentType = contentTypeFor(path: resourcePath)
        sendResponse(status: 200, contentType: contentType, body: data)
    }

    private func sendJson<T: Encodable>(_ value: T) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else {
            sendResponse(status: 500, contentType: "text/plain; charset=utf-8", body: "Error encoding JSON")
            return
        }
        sendResponse(status: 200, contentType: "application/json; charset=utf-8", body: data)
    }

    private func sendJsonDictionary(_ value: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]) else {
            sendResponse(status: 500, contentType: "text/plain; charset=utf-8", body: "Error encoding JSON")
            return
        }
        sendResponse(status: 200, contentType: "application/json; charset=utf-8", body: data)
    }

    private func sendResponse(status: Int, contentType: String, body: String) {
        sendResponse(status: status, contentType: contentType, body: Data(body.utf8))
    }

    private func sendResponse(status: Int, contentType: String, body: Data) {
        let header = "HTTP/1.1 \(status) \(statusText(status))\r\n" +
            "Content-Type: \(contentType)\r\n" +
            "Cache-Control: no-store\r\n" +
            "Content-Length: \(body.count)\r\n" +
            "Connection: close\r\n\r\n"
        var payload = Data(header.utf8)
        payload.append(body)
        connection.send(content: payload, completion: .contentProcessed { _ in
            self.connection.cancel()
            self.finish()
        })
    }

    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        onClose()
    }

    private func contentTypeFor(path: String) -> String {
        if path.hasSuffix(".html") { return "text/html; charset=utf-8" }
        if path.hasSuffix(".css") { return "text/css; charset=utf-8" }
        if path.hasSuffix(".js") { return "application/javascript; charset=utf-8" }
        if path.hasSuffix(".svg") { return "image/svg+xml" }
        if path.hasSuffix(".ts") { return "text/plain; charset=utf-8" }
        return "application/octet-stream"
    }

    private func statusText(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        default: return "OK"
        }
    }
}

private struct HttpRequest {
    let method: String
    let path: String
}

private func isoString(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: date)
}

private func writeDiscoveryFile(port: UInt16) {
    guard let url = discoveryFileURL() else { return }
    let payload: [String: Any] = [
        "port": port,
        "host": "127.0.0.1",
        "pid": ProcessInfo.processInfo.processIdentifier,
        "startedAt": isoString(Date())
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) else {
        return
    }
    try? data.write(to: url, options: .atomic)
}

private func cleanupDiscoveryFile() {
    guard let url = discoveryFileURL() else { return }
    try? FileManager.default.removeItem(at: url)
}

private func readDiscoveryPort() -> UInt16? {
    guard let url = discoveryFileURL(),
          let data = try? Data(contentsOf: url),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let port = json["port"] as? Int
    else {
        return nil
    }
    return UInt16(port)
}

private func discoveryFileURL() -> URL? {
    guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
        return nil
    }
    let directory = base.appendingPathComponent("AgentBuffer", isDirectory: true)
    do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    } catch {
        return nil
    }
    return directory.appendingPathComponent("metrics-server.json")
}

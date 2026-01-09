import CryptoKit
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
        let context = ConnectionContext(connection: connection, engine: engine, queue: queue) { [weak self] in
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
    private let queue: DispatchQueue
    private let onClose: () -> Void
    private var didFinish = false
    private var webSocketSession: WebSocketSession?

    init(connection: NWConnection, engine: MetricsEngine, queue: DispatchQueue, onClose: @escaping () -> Void) {
        self.connection = connection
        self.engine = engine
        self.queue = queue
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
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let separatorIndex = line.firstIndex(of: ":") else { continue }
            let name = line[..<separatorIndex].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: separatorIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                headers[name] = value
            }
        }
        buffer.removeSubrange(0..<range.upperBound)
        return HttpRequest(method: method, path: path, headers: headers)
    }

    private func respond(to request: HttpRequest) {
        if isWebSocketUpgrade(request) {
            handleWebSocket(request)
            return
        }
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

    private func isWebSocketUpgrade(_ request: HttpRequest) -> Bool {
        let upgrade = request.headers["upgrade"]?.lowercased() ?? ""
        let connectionHeader = request.headers["connection"]?.lowercased() ?? ""
        return upgrade == "websocket" && connectionHeader.contains("upgrade")
    }

    private func handleWebSocket(_ request: HttpRequest) {
        guard request.method.uppercased() == "GET" else {
            sendResponse(status: 405, contentType: "text/plain; charset=utf-8", body: "Method not allowed")
            return
        }
        let components = URLComponents(string: "http://localhost\(request.path)")
        let path = components?.path ?? request.path
        guard path == "/api/live" else {
            sendResponse(status: 404, contentType: "text/plain; charset=utf-8", body: "Not found")
            return
        }
        guard let key = request.headers["sec-websocket-key"],
              let accept = webSocketAcceptKey(key) else {
            sendResponse(status: 400, contentType: "text/plain; charset=utf-8", body: "Bad request")
            return
        }
        let response = "HTTP/1.1 101 Switching Protocols\r\n" +
            "Upgrade: websocket\r\n" +
            "Connection: Upgrade\r\n" +
            "Sec-WebSocket-Accept: \(accept)\r\n\r\n"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            if error != nil {
                self.connection.cancel()
                self.finish()
                return
            }
            let session = WebSocketSession(
                connection: self.connection,
                engine: self.engine,
                queue: self.queue,
                initialBuffer: self.buffer
            ) { [weak self] in
                self?.finish()
            }
            self.buffer = Data()
            self.webSocketSession = session
            session.start()
        })
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

private struct LiveMetricsSnapshot: Codable {
    let type: String
    let summary: MetricsSummary
    let timeseries: MetricsTimeseriesResponse
}

private struct LiveControlMessage: Decodable {
    let type: String
    let window: String?
}

private enum WebSocketOpcode: UInt8 {
    case continuation = 0x0
    case text = 0x1
    case close = 0x8
    case ping = 0x9
    case pong = 0xA
}

private struct WebSocketFrame {
    let fin: Bool
    let opcode: WebSocketOpcode
    let payload: Data
}

private final class WebSocketSession {
    private let connection: NWConnection
    private let engine: MetricsEngine
    private let queue: DispatchQueue
    private let onClose: () -> Void
    private var buffer: Data
    private var timer: DispatchSourceTimer?
    private var didClose = false
    private var currentWindow = "24h"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let allowedWindows: Set<String> = ["1h", "24h", "7d"]

    init(
        connection: NWConnection,
        engine: MetricsEngine,
        queue: DispatchQueue,
        initialBuffer: Data,
        onClose: @escaping () -> Void
    ) {
        self.connection = connection
        self.engine = engine
        self.queue = queue
        self.onClose = onClose
        self.buffer = initialBuffer
    }

    func start() {
        scheduleTimer()
        sendSnapshot()
        receive()
    }

    private func scheduleTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .seconds(5), repeating: .seconds(5))
        timer.setEventHandler { [weak self] in
            self?.sendSnapshot()
        }
        timer.resume()
        self.timer = timer
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.buffer.append(data)
                while let frame = self.parseFrame() {
                    self.handleFrame(frame)
                }
            }
            if isComplete || error != nil {
                self.close()
                return
            }
            self.receive()
        }
    }

    private func handleFrame(_ frame: WebSocketFrame) {
        guard frame.fin else { return }
        switch frame.opcode {
        case .text:
            handleText(frame.payload)
        case .ping:
            sendFrame(opcode: .pong, payload: frame.payload)
        case .close:
            sendFrame(opcode: .close, payload: Data())
            close()
        case .pong, .continuation:
            break
        }
    }

    private func handleText(_ payload: Data) {
        guard let message = try? decoder.decode(LiveControlMessage.self, from: payload) else {
            return
        }
        guard message.type == "window", let window = message.window, allowedWindows.contains(window) else {
            return
        }
        currentWindow = window
        sendSnapshot()
    }

    private func sendSnapshot() {
        let stepSeconds = windowStepSeconds(for: currentWindow)
        let summary = engine.summary()
        let timeseries = engine.timeseries(windowKey: currentWindow, stepSeconds: stepSeconds)
        let snapshot = LiveMetricsSnapshot(type: "snapshot", summary: summary, timeseries: timeseries)
        guard let payload = try? encoder.encode(snapshot) else { return }
        sendFrame(opcode: .text, payload: payload)
    }

    private func sendFrame(opcode: WebSocketOpcode, payload: Data) {
        var frame = Data()
        frame.append(0x80 | opcode.rawValue)
        let length = payload.count
        if length < 126 {
            frame.append(UInt8(length))
        } else if length <= 65535 {
            frame.append(126)
            let lengthBytes: [UInt8] = [
                UInt8((length >> 8) & 0xff),
                UInt8(length & 0xff)
            ]
            frame.append(contentsOf: lengthBytes)
        } else {
            frame.append(127)
            let length64 = UInt64(length)
            let lengthBytes: [UInt8] = [
                UInt8((length64 >> 56) & 0xff),
                UInt8((length64 >> 48) & 0xff),
                UInt8((length64 >> 40) & 0xff),
                UInt8((length64 >> 32) & 0xff),
                UInt8((length64 >> 24) & 0xff),
                UInt8((length64 >> 16) & 0xff),
                UInt8((length64 >> 8) & 0xff),
                UInt8(length64 & 0xff)
            ]
            frame.append(contentsOf: lengthBytes)
        }
        frame.append(payload)
        connection.send(content: frame, completion: .contentProcessed { [weak self] error in
            if error != nil {
                self?.close()
            }
        })
    }

    private func parseFrame() -> WebSocketFrame? {
        guard buffer.count >= 2 else { return nil }
        let bytes = [UInt8](buffer)
        let first = bytes[0]
        let second = bytes[1]
        let fin = (first & 0x80) != 0
        guard let opcode = WebSocketOpcode(rawValue: first & 0x0f) else {
            close()
            return nil
        }
        var length = Int(second & 0x7f)
        var index = 2
        if length == 126 {
            guard bytes.count >= index + 2 else { return nil }
            length = Int(UInt16(bytes[index]) << 8 | UInt16(bytes[index + 1]))
            index += 2
        } else if length == 127 {
            guard bytes.count >= index + 8 else { return nil }
            var length64: UInt64 = 0
            for offset in 0..<8 {
                length64 = (length64 << 8) | UInt64(bytes[index + offset])
            }
            if length64 > UInt64(Int.max) {
                close()
                return nil
            }
            length = Int(length64)
            index += 8
        }
        let masked = (second & 0x80) != 0
        var maskKey: [UInt8] = []
        if masked {
            guard bytes.count >= index + 4 else { return nil }
            maskKey = Array(bytes[index..<(index + 4)])
            index += 4
        }
        guard bytes.count >= index + length else { return nil }
        var payload = Data(bytes[index..<(index + length)])
        buffer.removeSubrange(0..<(index + length))
        if masked {
            var payloadBytes = [UInt8](payload)
            for i in 0..<payloadBytes.count {
                payloadBytes[i] ^= maskKey[i % 4]
            }
            payload = Data(payloadBytes)
        }
        return WebSocketFrame(fin: fin, opcode: opcode, payload: payload)
    }

    private func windowStepSeconds(for window: String) -> Int {
        return window == "7d" ? 300 : 60
    }

    private func close() {
        guard !didClose else { return }
        didClose = true
        timer?.cancel()
        timer = nil
        connection.cancel()
        onClose()
    }
}

private struct HttpRequest {
    let method: String
    let path: String
    let headers: [String: String]
}

private func webSocketAcceptKey(_ key: String) -> String? {
    let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let magic = trimmed + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
    let hash = Insecure.SHA1.hash(data: Data(magic.utf8))
    return Data(hash).base64EncodedString()
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

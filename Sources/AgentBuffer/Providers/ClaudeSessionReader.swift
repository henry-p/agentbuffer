import Foundation

final class ClaudeSessionReader: AgentProvider {
    let baseURL: URL
    let type: AgentType = .claude
    private let fileManager = FileManager.default
    private var pidSessionCache: [Int: URL] = [:]
    private var sessionTrackers: [Int: SessionTracker] = [:]
    private static var lastLoggedPidsSignature: String = ""

    init(baseURL: URL = ClaudeSessionReader.defaultBaseURL()) {
        self.baseURL = baseURL
    }

    static func defaultBaseURL() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let projects = home.appendingPathComponent(".claude/projects")
        if FileManager.default.fileExists(atPath: projects.path) {
            return projects
        }
        return home.appendingPathComponent(".claude")
    }

    var sessionRoots: [URL] {
        fileManager.fileExists(atPath: baseURL.path) ? [baseURL] : []
    }

    func readStates() -> [AgentState] {
        let entries = activeSessionEntries()
        var states: [AgentState] = []
        for entry in entries {
            if let state = updateTracker(for: entry.pid, url: entry.url) {
                states.append(state)
            }
        }
        return states
    }

    private struct SessionTracker {
        var url: URL
        var lastFileSize: UInt64
        var lastUserDate: Date?
        var lastAssistantDate: Date?
        var lastEvent: TurnEvent?
        var lastLoggedState: String?
        var lastUserMessage: String?
        var sessionStartDate: Date?

        init(url: URL) {
            self.url = url
            self.lastFileSize = 0
            self.lastUserDate = nil
            self.lastAssistantDate = nil
            self.lastEvent = nil
            self.lastLoggedState = nil
            self.lastUserMessage = nil
            self.sessionStartDate = ClaudeSessionReader.sessionStartDate(from: url)
        }
    }

    private enum TurnEvent {
        case user
        case assistant
    }

    private func activeSessionEntries() -> [(pid: Int, url: URL)] {
        let pids = ClaudeSessionReader.claudePids()
        guard !pids.isEmpty else {
            pidSessionCache.removeAll()
            sessionTrackers.removeAll()
            return []
        }
        let pidSet = Set(pids)
        pidSessionCache = pidSessionCache.filter { pidSet.contains($0.key) }
        sessionTrackers = sessionTrackers.filter { pidSet.contains($0.key) }

        var results: [(pid: Int, url: URL)] = []
        for pid in pids {
            let files = sessionFiles(for: pid)
            if let url = mostRecentFile(in: files) {
                let cached = pidSessionCache[pid]
                pidSessionCache[pid] = url
                results.append((pid, url))
                if Settings.devModeEnabled, cached?.path != url.path {
                    NSLog("[AgentBuffer] claude pid=%d session=%@", pid, url.lastPathComponent)
                }
            } else if let cached = pidSessionCache[pid] {
                results.append((pid, cached))
            }
        }
        return results
    }

    private func mostRecentFile(in files: [URL]) -> URL? {
        guard !files.isEmpty else {
            return nil
        }
        var bestURL: URL?
        var bestDate: Date?
        for url in files {
            let attrs = try? fileManager.attributesOfItem(atPath: url.path)
            let modified = attrs?[.modificationDate] as? Date
            if let modified {
                if bestDate == nil || modified > bestDate! {
                    bestDate = modified
                    bestURL = url
                }
            } else if bestURL == nil {
                bestURL = url
            }
        }
        return bestURL ?? files.first
    }

    private func sessionFiles(for pid: Int) -> [URL] {
        guard let output = ClaudeSessionReader.runCommand(
            "/usr/sbin/lsof",
            arguments: ["-p", String(pid), "-Fn"]
        ) else {
            return []
        }
        let basePath = baseURL.path
        var results: [URL] = []
        for rawLine in output.split(whereSeparator: \.isNewline) {
            guard rawLine.first == "n" else {
                continue
            }
            let path = String(rawLine.dropFirst())
            guard path.hasPrefix(basePath), path.hasSuffix(".jsonl") else {
                continue
            }
            results.append(URL(fileURLWithPath: path))
        }
        return results
    }

    private static func claudePids() -> [Int] {
        guard let output = runCommand("/usr/bin/pgrep", arguments: ["-f", "claude"]) else {
            return []
        }
        let candidates = output.split(whereSeparator: \.isNewline).compactMap { Int($0) }
        var results: [Int] = []
        for pid in candidates {
            guard let command = runCommand("/bin/ps", arguments: ["-o", "command=", "-p", String(pid)])?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() else {
                continue
            }
            guard command.contains("claude") else {
                continue
            }
            guard let open = runCommand("/usr/sbin/lsof", arguments: ["-p", String(pid), "-Fn"]) else {
                continue
            }
            let hasSession = open.split(whereSeparator: \.isNewline).contains { line in
                guard line.first == "n" else { return false }
                let path = String(line.dropFirst())
                return path.hasPrefix(defaultBaseURL().path) && path.hasSuffix(".jsonl")
            }
            if hasSession {
                results.append(pid)
            }
        }
        if Settings.devModeEnabled {
            let signature = results.map { String($0) }.joined(separator: ",")
            if signature != lastLoggedPidsSignature {
                NSLog("[AgentBuffer] claudePids=%@", signature)
                lastLoggedPidsSignature = signature
            }
        }
        return results
    }

    private static func runCommand(_ path: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }

    private func updateTracker(for pid: Int, url: URL) -> AgentState? {
        let attrs = try? fileManager.attributesOfItem(atPath: url.path)
        let size = (attrs?[.size] as? NSNumber)?.uint64Value ?? 0

        var tracker = sessionTrackers[pid] ?? SessionTracker(url: url)
        if tracker.url.path != url.path {
            tracker = SessionTracker(url: url)
        }
        if tracker.sessionStartDate == nil {
            tracker.sessionStartDate = ClaudeSessionReader.sessionStartDate(from: url)
        }
        if tracker.lastFileSize != size || tracker.lastEvent == nil {
            let scan = scanLatestEvents(url: url, size: size)
            tracker.lastUserDate = scan.lastUserDate
            tracker.lastAssistantDate = scan.lastAssistantDate
            tracker.lastEvent = scan.lastEvent
            tracker.lastUserMessage = scan.lastUserMessage
            tracker.lastFileSize = size
        }

        sessionTrackers[pid] = tracker
        guard tracker.lastUserDate != nil || tracker.lastAssistantDate != nil else {
            return nil
        }
        let state: AgentRunState
        if let lastEvent = tracker.lastEvent {
            state = lastEvent == .user ? .running : .finished
        } else if let lastUserDate = tracker.lastUserDate {
            if tracker.lastAssistantDate == nil || lastUserDate > tracker.lastAssistantDate! {
                state = .running
            } else {
                state = .finished
            }
        } else {
            state = .finished
        }
        let finishedAt = tracker.lastAssistantDate?.timeIntervalSince1970
        if Settings.devModeEnabled, tracker.lastLoggedState != state.rawValue {
            let userStamp = tracker.lastUserDate?.description ?? "nil"
            let assistantStamp = tracker.lastAssistantDate?.description ?? "nil"
            NSLog("[AgentBuffer] claude session=%@ pid=%d state=%@ lastUser=%@ lastAssistant=%@", url.lastPathComponent, pid, state.rawValue, userStamp, assistantStamp)
            tracker.lastLoggedState = state.rawValue
        }
        sessionTrackers[pid] = tracker
        return AgentState(
            id: url.deletingPathExtension().lastPathComponent,
            state: state,
            finishedAt: finishedAt,
            lastUserAt: (tracker.lastUserDate ?? tracker.sessionStartDate)?.timeIntervalSince1970,
            agentType: .claude,
            lastUserMessage: tracker.lastUserMessage,
            pid: pid
        )
    }

    private static func sessionStartDate(from url: URL) -> Date? {
        let name = url.deletingPathExtension().lastPathComponent
        if let range = name.range(
            of: #"\d{4}-\d{2}-\d{2}[T_]\d{2}[-:]\d{2}[-:]\d{2}"#,
            options: .regularExpression
        ) {
            let token = String(name[range]).replacingOccurrences(of: "_", with: "T")
            let parts = token.split(separator: "T", maxSplits: 1, omittingEmptySubsequences: true)
            if parts.count == 2 {
                let datePart = parts[0]
                let timePart = parts[1].replacingOccurrences(of: "-", with: ":")
                let isoString = "\(datePart)T\(timePart)Z"
                if let parsed = parseTimestamp(isoString) {
                    return parsed
                }
            }
        }
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        if let created = attrs?[.creationDate] as? Date {
            return created
        }
        return attrs?[.modificationDate] as? Date
    }

    private func scanLatestEvents(
        url: URL,
        size: UInt64
    ) -> (lastUserDate: Date?, lastAssistantDate: Date?, lastEvent: TurnEvent?, lastUserMessage: String?) {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return (nil, nil, nil, nil)
        }
        defer { try? handle.close() }
        let chunkSize = LogScanConstants.chunkSizeBytes
        var cursor = size
        var carry = Data()
        var lastUserDate: Date?
        var lastAssistantDate: Date?
        var lastEvent: TurnEvent?
        var lastUserMessage: String?

        func userMessageText(from event: [String: Any]) -> String? {
            guard let role = messageRole(from: event), role == "user" else {
                return nil
            }
            if let userType = userType(from: event), userType != "external" {
                return nil
            }
            let text = extractMessageText(from: event)
            let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }

        func classifyEvent(_ event: [String: Any]) -> (isUser: Bool, isAssistant: Bool, timestamp: Date?) {
            guard let timestamp = event["timestamp"] as? String,
                  let parsed = ClaudeSessionReader.parseTimestamp(timestamp) else {
                return (false, false, nil)
            }
            if let role = messageRole(from: event) {
                if role == "user" {
                    if let userType = userType(from: event), userType != "external" {
                        return (false, false, nil)
                    }
                    return (true, false, parsed)
                }
                if role == "assistant" {
                    return (false, true, parsed)
                }
            }
            return (false, false, nil)
        }

        while cursor > 0 && (lastEvent == nil || lastUserDate == nil || lastAssistantDate == nil || lastUserMessage == nil) {
            let readSize = Int(min(chunkSize, cursor))
            cursor -= UInt64(readSize)
            if (try? handle.seek(toOffset: cursor)) == nil {
                break
            }
            let chunk = (try? handle.read(upToCount: readSize)) ?? Data()
            if chunk.isEmpty {
                break
            }
            var buffer = Data()
            buffer.append(chunk)
            buffer.append(carry)
            let parts = buffer.split(separator: LogScanConstants.newlineByte, omittingEmptySubsequences: false)
            var startIndex = 0
            if cursor > 0 {
                if let first = parts.first {
                    carry = Data(first)
                } else {
                    carry = Data()
                }
                startIndex = 1
            } else {
                carry = Data()
            }
            if startIndex < parts.count {
                for rawLine in parts[startIndex...].reversed() {
                    if lastEvent != nil && lastUserDate != nil && lastAssistantDate != nil {
                        if lastUserMessage != nil {
                            break
                        }
                    }
                    var lineSlice = rawLine
                    if lineSlice.last == LogScanConstants.carriageReturnByte {
                        lineSlice = lineSlice.dropLast()
                    }
                    if lineSlice.isEmpty {
                        continue
                    }
                    let lineData = Data(lineSlice)
                    guard let event = parseEvent(from: lineData) else {
                        continue
                    }
                    let classification = classifyEvent(event)
                    if let timestamp = classification.timestamp {
                        if classification.isUser, lastUserDate == nil {
                            lastUserDate = timestamp
                        }
                        if classification.isAssistant, lastAssistantDate == nil {
                            lastAssistantDate = timestamp
                        }
                        if lastEvent == nil {
                            if classification.isUser {
                                lastEvent = .user
                            } else if classification.isAssistant {
                                lastEvent = .assistant
                            }
                        }
                    }
                    if lastUserMessage == nil, classification.isUser, let message = userMessageText(from: event) {
                        lastUserMessage = message
                    }
                }
            }
        }
        return (lastUserDate, lastAssistantDate, lastEvent, lastUserMessage)
    }

    private func parseEvent(from data: Data) -> [String: Any]? {
        guard let raw = try? JSONSerialization.jsonObject(with: data, options: []) else {
            return nil
        }
        return raw as? [String: Any]
    }

    private func messageRole(from event: [String: Any]) -> String? {
        if let message = event["message"] as? [String: Any],
           let role = message["role"] as? String {
            let lower = role.lowercased()
            if lower == "human" {
                return "user"
            }
            return lower
        }
        if let role = event["role"] as? String {
            let lower = role.lowercased()
            if lower == "human" {
                return "user"
            }
            return lower
        }
        if let type = event["type"] as? String {
            let lower = type.lowercased()
            if lower == "user" || lower == "assistant" {
                return lower
            }
            if lower.contains("user") {
                return "user"
            }
            if lower.contains("assistant") {
                return "assistant"
            }
        }
        return nil
    }

    private func userType(from event: [String: Any]) -> String? {
        if let userType = event["userType"] as? String {
            return userType.lowercased()
        }
        if let userType = event["user_type"] as? String {
            return userType.lowercased()
        }
        return nil
    }

    private func extractMessageText(from event: [String: Any]) -> String? {
        if let message = event["message"] as? [String: Any] {
            if let content = message["content"] {
                return extractText(from: content)
            }
        }
        if let content = event["content"] {
            return extractText(from: content)
        }
        if let text = event["text"] as? String {
            return decodeTextIfNeeded(text)
        }
        return nil
    }

    private func extractText(from value: Any) -> String? {
        if let text = value as? String {
            let decoded = decodeTextIfNeeded(text)
            return decoded.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : decoded
        }
        if let items = value as? [Any] {
            var parts: [String] = []
            for item in items {
                if let dict = item as? [String: Any] {
                    if let type = dict["type"] as? String {
                        let lower = type.lowercased()
                        if !lower.contains("text") {
                            continue
                        }
                    }
                    if let text = dict["text"] as? String {
                        let decoded = decodeTextIfNeeded(text)
                        if !decoded.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            parts.append(decoded)
                        }
                        continue
                    }
                    if let text = dict["content"] as? String {
                        let decoded = decodeTextIfNeeded(text)
                        if !decoded.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            parts.append(decoded)
                        }
                        continue
                    }
                } else if let text = item as? String {
                    let decoded = decodeTextIfNeeded(text)
                    if !decoded.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        parts.append(decoded)
                    }
                }
            }
            let combined = parts.joined(separator: "\n")
            return combined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : combined
        }
        return nil
    }

    private func decodeTextIfNeeded(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 16 else {
            return text
        }
        let cleaned = trimmed.replacingOccurrences(of: "\n", with: "")
        guard cleaned.count % 4 == 0 else {
            return text
        }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=")
        guard cleaned.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return text
        }
        guard let data = Data(base64Encoded: cleaned),
              let decoded = String(data: data, encoding: .utf8) else {
            return text
        }
        let controlCharacters = decoded.unicodeScalars.filter {
            CharacterSet.controlCharacters.contains($0)
                && $0 != "\n"
                && $0 != "\t"
                && $0 != "\r"
        }
        if !decoded.isEmpty, Double(controlCharacters.count) / Double(decoded.unicodeScalars.count) < 0.1 {
            return decoded
        }
        return text
    }

    private static let isoFormatterFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static func parseTimestamp(_ raw: String) -> Date? {
        if let date = isoFormatterFractional.date(from: raw) {
            return date
        }
        return isoFormatter.date(from: raw)
    }

    func currentPids() -> [Int] {
        ClaudeSessionReader.claudePids()
    }
}

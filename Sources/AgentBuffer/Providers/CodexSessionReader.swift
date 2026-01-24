import Foundation

struct CodexEvent: Decodable {
    let timestamp: String?
    let type: String
    let payload: CodexPayload?
    let instructions: String?
}

struct CodexPayload: Decodable {
    let type: String?
    let role: String?
    let content: [CodexContent]?
    let instructions: String?
    let message: String?
}

struct CodexContent: Decodable {
    let type: String?
    let text: String?
}

final class CodexSessionReader: AgentProvider {
    let baseURL: URL
    let type: AgentType = .codex
    private let fileManager = FileManager.default
    private var pidSessionCache: [Int: URL] = [:]
    private var sessionTrackers: [Int: SessionTracker] = [:]
    private static var lastLoggedPidsSignature: String = ""

    init(baseURL: URL = CodexSessionReader.defaultBaseURL()) {
        self.baseURL = baseURL
    }

    static func defaultBaseURL() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".codex/sessions")
    }

    var sessionRoots: [URL] {
        [baseURL]
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
        var sessionInstructions: String?
        var lastUserMessage: String?
        var sessionStartDate: Date?

        init(url: URL) {
            self.url = url
            self.lastFileSize = 0
            self.lastUserDate = nil
            self.lastAssistantDate = nil
            self.lastEvent = nil
            self.lastLoggedState = nil
            self.sessionInstructions = nil
            self.lastUserMessage = nil
            self.sessionStartDate = CodexSessionReader.sessionStartDate(from: url)
        }
    }

    private enum TurnEvent {
        case user
        case assistant
    }

    private func activeSessionEntries() -> [(pid: Int, url: URL)] {
        let pids = CodexSessionReader.codexPids()
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
                    NSLog("[AgentBuffer] pid=%d session=%@", pid, url.lastPathComponent)
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
        guard let output = CodexSessionReader.runCommand(
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

    private static func codexPids() -> [Int] {
        guard let output = runCommand("/usr/bin/pgrep", arguments: ["-f", "codex"]) else {
            return []
        }
        let candidates = output.split(whereSeparator: \.isNewline).compactMap { Int($0) }
        var results: [Int] = []
        for pid in candidates {
            guard let command = runCommand("/bin/ps", arguments: ["-o", "comm=", "-p", String(pid)])?
                .trimmingCharacters(in: .whitespacesAndNewlines) else {
                continue
            }
            let executable = URL(fileURLWithPath: command).lastPathComponent.lowercased()
            if executable != "codex" {
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
                NSLog("[AgentBuffer] codexPids=%@", signature)
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
            tracker.sessionStartDate = CodexSessionReader.sessionStartDate(from: url)
        }
        if tracker.sessionInstructions == nil {
            tracker.sessionInstructions = readSessionInstructions(url: url)
        }
        if tracker.lastFileSize != size || tracker.lastEvent == nil {
            let scan = scanLatestEvents(url: url, size: size, sessionInstructions: tracker.sessionInstructions)
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
            NSLog("[AgentBuffer] session=%@ pid=%d state=%@ lastUser=%@ lastAssistant=%@", url.lastPathComponent, pid, state.rawValue, userStamp, assistantStamp)
            tracker.lastLoggedState = state.rawValue
        }
        sessionTrackers[pid] = tracker
        return AgentState(
            id: url.deletingPathExtension().lastPathComponent,
            state: state,
            finishedAt: finishedAt,
            lastUserAt: (tracker.lastUserDate ?? tracker.sessionStartDate)?.timeIntervalSince1970,
            agentType: .codex,
            lastUserMessage: tracker.lastUserMessage,
            pid: pid
        )
    }

    private static func sessionStartDate(from url: URL) -> Date? {
        let name = url.deletingPathExtension().lastPathComponent
        guard let range = name.range(
            of: #"rollout-\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}"#,
            options: .regularExpression
        ) else {
            return nil
        }
        let token = String(name[range]).replacingOccurrences(of: "rollout-", with: "")
        let parts = token.split(separator: "T", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2 else {
            return nil
        }
        let datePart = parts[0]
        let timePart = parts[1].replacingOccurrences(of: "-", with: ":")
        let isoString = "\(datePart)T\(timePart)Z"
        return parseTimestamp(isoString)
    }

    private struct SessionMetaEnvelope: Decodable {
        let type: String
        let payload: SessionMetaPayload?
    }

    private struct SessionMetaPayload: Decodable {
        let instructions: String?
    }

    private func readSessionInstructions(url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? handle.close() }
        let chunkSize = 64 * 1024
        var buffer = Data()
        while buffer.count < 2 * 1024 * 1024 {
            let chunk = (try? handle.read(upToCount: chunkSize)) ?? Data()
            if chunk.isEmpty {
                break
            }
            if let newlineIndex = chunk.firstIndex(of: LogScanConstants.newlineByte) {
                buffer.append(chunk[..<newlineIndex])
                break
            }
            buffer.append(chunk)
        }
        guard !buffer.isEmpty else {
            return nil
        }
        let decoder = JSONDecoder()
        guard let meta = try? decoder.decode(SessionMetaEnvelope.self, from: buffer),
              meta.type == "session_meta" else {
            return nil
        }
        return meta.payload?.instructions
    }

    private func scanLatestEvents(
        url: URL,
        size: UInt64,
        sessionInstructions: String?
    ) -> (lastUserDate: Date?, lastAssistantDate: Date?, lastEvent: TurnEvent?, lastUserMessage: String?) {
        let decoder = JSONDecoder()
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

        func isShellCommandUserText(_ text: String) -> Bool {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("!") {
                return true
            }
            if trimmed.hasPrefix("<user_shell_command>") {
                return true
            }
            return false
        }

        func isAgentsInstructionText(_ trimmed: String) -> Bool {
            return trimmed.hasPrefix("# AGENTS.md instructions for ")
                || trimmed.hasPrefix("AGENTS.md instructions for ")
        }

        func isBootstrapUserText(_ text: String) -> Bool {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return true
            }
            if trimmed.hasPrefix("<environment_context>") {
                return true
            }
            if trimmed.hasPrefix("<user_instructions>") {
                return true
            }
            if isAgentsInstructionText(trimmed) {
                return true
            }
            if let sessionInstructions, !sessionInstructions.isEmpty,
               trimmed.contains(sessionInstructions) {
                return true
            }
            return false
        }

        func isIgnoredUserText(_ text: String) -> Bool {
            if isBootstrapUserText(text) {
                return true
            }
            return isShellCommandUserText(text)
        }

        func userMessageText(from event: CodexEvent) -> String? {
            guard let payload = event.payload else {
                return nil
            }
            if event.type == "event_msg", payload.type == "user_message" {
                if let message = payload.message {
                    return message
                }
                return payload.instructions
            }
            if event.type == "response_item",
               payload.type == "message",
               payload.role == "user" {
                let parts = payload.content?.compactMap { $0.text } ?? []
                if !parts.isEmpty {
                    return parts.joined(separator: "\n")
                }
                return payload.instructions
            }
            return nil
        }

        func classifyEvent(_ event: CodexEvent) -> (isUser: Bool, isAssistant: Bool, timestamp: Date?) {
            guard let timestamp = event.timestamp,
                  let parsed = CodexSessionReader.parseTimestamp(timestamp) else {
                return (false, false, nil)
            }
            if event.type == "compacted" {
                return (false, true, parsed)
            }
            if event.type == "event_msg", let payload = event.payload {
                if payload.type == "context_compacted" {
                    return (false, true, parsed)
                }
                if payload.type == "user_message" {
                    if let text = userMessageText(from: event), isIgnoredUserText(text) {
                        return (false, false, nil)
                    }
                    return (true, false, parsed)
                }
                if payload.type == "agent_message" || payload.type == "assistant_message" {
                    return (false, true, parsed)
                }
            }
            if event.type == "response_item", let payload = event.payload,
               payload.type == "message", let role = payload.role {
                if role == "user" {
                    if let text = userMessageText(from: event), isIgnoredUserText(text) {
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
                    guard let event = try? decoder.decode(CodexEvent.self, from: lineData) else {
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
                        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty && !isIgnoredUserText(trimmed) {
                            lastUserMessage = trimmed
                        }
                    }
                }
            }
        }
        return (lastUserDate, lastAssistantDate, lastEvent, lastUserMessage)
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
        CodexSessionReader.codexPids()
    }
}

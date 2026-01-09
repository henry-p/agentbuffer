import Foundation

private enum LogScanConstants {
    static let chunkSizeBytes: UInt64 = 512 * 1024
    static let newlineByte: UInt8 = 0x0A
    static let carriageReturnByte: UInt8 = 0x0D
}

struct StatusSnapshot: Equatable {
    let runningCount: Int
    let finishedCount: Int
    let totalCount: Int
    let progressPercent: Double
    let runningAgents: [AgentListItem]
    let idleAgents: [AgentListItem]
    let mostRecentFinishedPid: Int?

    static let empty = StatusSnapshot(
        runningCount: 0,
        finishedCount: 0,
        totalCount: 0,
        progressPercent: 0,
        runningAgents: [],
        idleAgents: [],
        mostRecentFinishedPid: nil
    )

    var toolTip: String {
        let percent = Int(round(progressPercent))
        return "Total: \(totalCount) (\(percent)%)"
    }
}

enum AgentType: String, Equatable {
    case codex
    case claude
    case unknown
}

enum AgentRunState: String, Equatable {
    case running
    case finished
}

struct AgentListItem: Equatable {
    let id: String
    let type: AgentType
    let title: String
    let pid: Int?
    let runtimeSeconds: TimeInterval?

    init(id: String, type: AgentType, title: String, pid: Int? = nil, runtimeSeconds: TimeInterval? = nil) {
        self.id = id
        self.type = type
        self.title = title
        self.pid = pid
        self.runtimeSeconds = runtimeSeconds
    }

    static func == (lhs: AgentListItem, rhs: AgentListItem) -> Bool {
        lhs.id == rhs.id
            && lhs.type == rhs.type
            && lhs.title == rhs.title
            && lhs.pid == rhs.pid
    }
}

struct AgentState {
    let id: String
    let state: AgentRunState
    let finishedAt: TimeInterval?
    let lastUserAt: TimeInterval?
    let agentType: AgentType
    let lastUserMessage: String?
    let pid: Int?
}

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

final class CodexSessionReader {
    private let baseURL: URL
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

final class ClaudeSessionReader {
    private let baseURL: URL
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

final class StatusReader {
    let codexSessionsURL: URL
    let claudeSessionsURL: URL
    private let codexReader: CodexSessionReader
    private let claudeReader: ClaudeSessionReader

    init(
        codexSessionsURL: URL = CodexSessionReader.defaultBaseURL(),
        claudeSessionsURL: URL = ClaudeSessionReader.defaultBaseURL()
    ) {
        self.codexSessionsURL = codexSessionsURL
        self.claudeSessionsURL = claudeSessionsURL
        self.codexReader = CodexSessionReader(baseURL: codexSessionsURL)
        self.claudeReader = ClaudeSessionReader(baseURL: claudeSessionsURL)
    }

    func readSnapshot() -> StatusSnapshot {
        let codexStates = codexReader.readStates()
        let claudeStates = claudeReader.readStates()

        let codexPids = codexReader.currentPids()
        let knownCodexPids = Set(codexStates.compactMap { $0.pid })
        let missingCodexPids = codexPids.filter { !knownCodexPids.contains($0) }

        let claudePids = claudeReader.currentPids()
        let knownClaudePids = Set(claudeStates.compactMap { $0.pid })
        let missingClaudePids = claudePids.filter { !knownClaudePids.contains($0) }

        let placeholders = missingCodexPids.map { pid in
            AgentState(
                id: "pid-\(pid)",
                state: .finished,
                finishedAt: nil,
                lastUserAt: nil,
                agentType: .codex,
                lastUserMessage: nil,
                pid: pid
            )
        } + missingClaudePids.map { pid in
            AgentState(
                id: "pid-\(pid)",
                state: .finished,
                finishedAt: nil,
                lastUserAt: nil,
                agentType: .claude,
                lastUserMessage: nil,
                pid: pid
            )
        }

        return StatusEvaluator.evaluate(states: codexStates + claudeStates + placeholders)
    }

    func currentPids() -> [Int] {
        codexReader.currentPids() + claudeReader.currentPids()
    }

    var sessionRoots: [URL] {
        var roots: [URL] = [codexSessionsURL]
        if FileManager.default.fileExists(atPath: claudeSessionsURL.path) {
            roots.append(claudeSessionsURL)
        }
        return roots
    }
}

enum StatusEvaluator {
    static func evaluate(states: [AgentState]) -> StatusSnapshot {
        var runningStates: [AgentState] = []
        var finishedStates: [AgentState] = []
        runningStates.reserveCapacity(states.count)
        finishedStates.reserveCapacity(states.count)
        for state in states {
            switch state.state {
            case .running:
                runningStates.append(state)
            case .finished:
                finishedStates.append(state)
            }
        }
        let running = runningStates.count
        let finished = finishedStates.count
        let total = states.count
        let now = Date().timeIntervalSince1970
        var runningAgents: [AgentListItem] = []
        runningAgents.reserveCapacity(runningStates.count)
        for state in runningStates {
            let runtime: TimeInterval?
            if let lastUserAt = state.lastUserAt {
                runtime = max(0, now - lastUserAt)
            } else {
                runtime = nil
            }
            runningAgents.append(
                AgentListItem(
                    id: state.id,
                    type: state.agentType,
                    title: clipTitle(state.lastUserMessage),
                    pid: state.pid,
                    runtimeSeconds: runtime
                )
            )
        }
        runningAgents.sort { ($0.runtimeSeconds ?? 0) > ($1.runtimeSeconds ?? 0) }
        let idleAgents = finishedStates.map { state in
            AgentListItem(
                id: state.id,
                type: state.agentType,
                title: clipTitle(state.lastUserMessage, fallback: "Idle…"),
                pid: state.pid,
                runtimeSeconds: nil
            )
        }
        let mostRecentFinishedPid = finishedStates
            .compactMap { state -> (TimeInterval, Int)? in
                guard let finishedAt = state.finishedAt, let pid = state.pid else {
                    return nil
                }
                return (finishedAt, pid)
            }
            .max(by: { $0.0 < $1.0 })?
            .1

        let progressPercent: Double
        if total == 0 {
            progressPercent = 0
        } else {
            progressPercent = (Double(running) / Double(total)) * Settings.percentMax
        }

        return StatusSnapshot(
            runningCount: running,
            finishedCount: finished,
            totalCount: total,
            progressPercent: progressPercent,
            runningAgents: runningAgents,
            idleAgents: idleAgents,
            mostRecentFinishedPid: mostRecentFinishedPid
        )
    }

    private static func clipTitle(_ raw: String?, fallback: String = "Running…") -> String {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return fallback
        }
        let lines = raw.split(whereSeparator: \.isNewline)
        let firstNonEmpty = lines.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let trimmed = firstNonEmpty?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            return fallback
        }
        let collapsed = trimmed.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        let maxLength = 60
        guard collapsed.count > maxLength else {
            return collapsed
        }
        let endIndex = collapsed.index(collapsed.startIndex, offsetBy: maxLength)
        let prefix = String(collapsed[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        return prefix + "…"
    }
}

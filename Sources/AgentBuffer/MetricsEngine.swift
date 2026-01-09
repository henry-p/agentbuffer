import Foundation

private enum MetricsConstants {
    static let cacheTTL: TimeInterval = 5
    static let reworkWindow: TimeInterval = 10 * 60
    static let histogramBuckets: [Int] = [0, 2, 5, 10, 20, 40, 60, 120, 240, 480]
    static let windowDefs: [(key: String, seconds: TimeInterval)] = [
        ("1h", 60 * 60),
        ("24h", 24 * 60 * 60),
        ("7d", 7 * 24 * 60 * 60)
    ]
}

final class MetricsEngine {
    private let baseURL: URL
    private var cache: (at: Date, data: MetricsSummary)?
    private let decoder = JSONDecoder()

    init(baseURL: URL = CodexSessionReader.defaultBaseURL()) {
        self.baseURL = baseURL
    }

    func summary(now: Date = Date()) -> MetricsSummary {
        if let cache, now.timeIntervalSince(cache.at) < MetricsConstants.cacheTTL {
            return cache.data
        }
        let summary = computeSummary(now: now)
        cache = (now, summary)
        return summary
    }

    func timeseries(windowKey: String, stepSeconds: Int, now: Date = Date()) -> MetricsTimeseriesResponse {
        let window = MetricsConstants.windowDefs.first { $0.key == windowKey } ?? MetricsConstants.windowDefs[1]
        let windowStart = now.timeIntervalSince1970 - window.seconds
        let windowEnd = now.timeIntervalSince1970
        let sessions = loadSessions(cutoff: now.addingTimeInterval(-window.seconds))
        let segments = sessions.map { computeSegments(events: $0.events, windowStart: windowStart, windowEnd: windowEnd) }
        let points = computeTimeseries(segmentsBySession: segments, windowStart: windowStart, windowEnd: windowEnd, stepSeconds: stepSeconds)
        return MetricsTimeseriesResponse(
            window: window.key,
            windowStart: windowStart,
            windowEnd: windowEnd,
            stepSeconds: stepSeconds,
            points: points
        )
    }

    private func computeSummary(now: Date) -> MetricsSummary {
        let maxWindowSeconds = MetricsConstants.windowDefs.map { $0.seconds }.max() ?? 0
        let cutoff = now.addingTimeInterval(-maxWindowSeconds)
        let sessions = loadSessions(cutoff: cutoff)
        let stats = buildTaskStats(sessions: sessions)
        var windows: [String: MetricsWindow] = [:]
        for window in MetricsConstants.windowDefs {
            let windowStart = now.timeIntervalSince1970 - window.seconds
            let windowEnd = now.timeIntervalSince1970
            windows[window.key] = computeWindowMetrics(
                sessions: sessions,
                stats: stats,
                windowStart: windowStart,
                windowEnd: windowEnd,
                idleThreshold: Settings.idleAlertThresholdPercent / 100.0
            )
        }
        let current = computeCurrentCounts(sessions: sessions, now: now)
        let summary = MetricsSummary(
            generatedAt: isoString(now),
            config: MetricsConfig(
                idleThreshold: Settings.idleAlertThresholdPercent / 100.0,
                baseDir: baseURL.path
            ),
            current: current,
            windows: windows
        )
        return summary
    }

    private func loadSessions(cutoff: Date) -> [MetricsSession] {
        let files = listSessionFiles(cutoff: cutoff)
        var sessions: [MetricsSession] = []
        sessions.reserveCapacity(files.count)
        for fileURL in files {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
                continue
            }
            let lines = content.split(whereSeparator: \.isNewline).map(String.init)
            guard !lines.isEmpty else { continue }
            let instructions = parseSessionInstructions(from: lines.first)
            var events: [MetricsEvent] = []
            events.reserveCapacity(lines.count)
            for line in lines {
                guard let data = line.data(using: .utf8),
                      let event = try? decoder.decode(CodexEvent.self, from: data),
                      let classified = classify(event: event, sessionInstructions: instructions) else {
                    continue
                }
                events.append(classified)
            }
            guard !events.isEmpty else { continue }
            events.sort { $0.t < $1.t }
            sessions.append(MetricsSession(id: fileURL.deletingPathExtension().lastPathComponent, events: events))
        }
        return sessions
    }

    private func listSessionFiles(cutoff: Date) -> [URL] {
        var result: [URL] = []
        guard FileManager.default.fileExists(atPath: baseURL.path) else {
            return result
        }
        let cutoffTime = cutoff.timeIntervalSince1970
        let enumerator = FileManager.default.enumerator(
            at: baseURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "jsonl" else { continue }
            let resourceValues = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey])
            let mtime = resourceValues?.contentModificationDate?.timeIntervalSince1970 ?? 0
            if mtime >= cutoffTime {
                result.append(fileURL)
            }
        }
        return result
    }
}

private struct MetricsSession {
    let id: String
    let events: [MetricsEvent]
}

private struct MetricsEvent {
    let t: TimeInterval
    let kind: MetricsEventKind
    let text: String?
}

private enum MetricsEventKind {
    case user
    case assistant
}

private struct TaskStat {
    let start: TimeInterval
    let end: TimeInterval
    let prompts: Int
    let text: String?
    let sessionId: String
}

private struct AssignmentStat {
    let time: TimeInterval
    let text: String?
    let sessionId: String
}

private struct ResponseStat {
    let assignedAt: TimeInterval
    let responseSeconds: TimeInterval
    let sessionId: String
}

private struct ReworkStat {
    let completionAt: TimeInterval
    let sessionId: String
}

private struct TaskStatsBundle {
    let tasks: [TaskStat]
    let assignments: [AssignmentStat]
    let responses: [ResponseStat]
    let reworks: [ReworkStat]
}

private struct Segment {
    let start: TimeInterval
    let end: TimeInterval
    let state: MetricsEventKind
}

private func buildTaskStats(sessions: [MetricsSession]) -> TaskStatsBundle {
    var tasks: [TaskStat] = []
    var assignments: [AssignmentStat] = []
    var responses: [ResponseStat] = []
    var reworks: [ReworkStat] = []

    for session in sessions {
        var currentTask: (start: TimeInterval, prompts: Int, text: String?)?
        var awaitingResponseSince: TimeInterval?
        var lastCompletion: (time: TimeInterval, text: String?)?
        var hadUser = false

        for event in session.events {
            switch event.kind {
            case .user:
                hadUser = true
                assignments.append(AssignmentStat(time: event.t, text: event.text, sessionId: session.id))
                if let awaiting = awaitingResponseSince {
                    responses.append(ResponseStat(
                        assignedAt: event.t,
                        responseSeconds: event.t - awaiting,
                        sessionId: session.id
                    ))
                    if let completion = lastCompletion,
                       event.t - completion.time <= MetricsConstants.reworkWindow,
                       isSimilarText(completion.text, event.text) {
                        reworks.append(ReworkStat(completionAt: completion.time, sessionId: session.id))
                    }
                    awaitingResponseSince = nil
                }
                if let task = currentTask {
                    currentTask = (task.start, task.prompts + 1, task.text)
                } else {
                    currentTask = (event.t, 1, event.text)
                }
            case .assistant:
                if let task = currentTask {
                    tasks.append(TaskStat(
                        start: task.start,
                        end: event.t,
                        prompts: task.prompts,
                        text: task.text,
                        sessionId: session.id
                    ))
                    lastCompletion = (time: event.t, text: task.text)
                    currentTask = nil
                }
                if hadUser {
                    awaitingResponseSince = event.t
                }
            }
        }
    }

    return TaskStatsBundle(tasks: tasks, assignments: assignments, responses: responses, reworks: reworks)
}

private func computeWindowMetrics(
    sessions: [MetricsSession],
    stats: TaskStatsBundle,
    windowStart: TimeInterval,
    windowEnd: TimeInterval,
    idleThreshold: Double
) -> MetricsWindow {
    let segmentsBySession = sessions.map { computeSegments(events: $0.events, windowStart: windowStart, windowEnd: windowEnd) }

    var runningSeconds: Double = 0
    var totalSeconds: Double = 0
    for segments in segmentsBySession {
        for segment in segments {
            let duration = max(0, segment.end - segment.start)
            totalSeconds += duration
            if segment.state == .user {
                runningSeconds += duration
            }
        }
    }
    let activeUtilization = totalSeconds > 0 ? runningSeconds / totalSeconds : 0

    let series = computeTimeseries(
        segmentsBySession: segmentsBySession,
        windowStart: windowStart,
        windowEnd: windowEnd,
        stepSeconds: 60
    )
    var idleMinutes: Double = 0
    var totalMinutes: Double = 0
    for point in series {
        guard point.total > 0 else { continue }
        totalMinutes += 1
        let idleRatio = 1 - point.utilization
        if idleRatio >= idleThreshold {
            idleMinutes += 1
        }
    }
    let idleOverThreshold = totalMinutes > 0 ? idleMinutes / totalMinutes : 0

    let tasksInWindow = stats.tasks.filter { $0.end >= windowStart && $0.end <= windowEnd }
    let assignmentsInWindow = stats.assignments.filter { $0.time >= windowStart && $0.time <= windowEnd }
    let responsesInWindow = stats.responses.filter { $0.assignedAt >= windowStart && $0.assignedAt <= windowEnd }
    let reworksInWindow = stats.reworks.filter { $0.completionAt >= windowStart && $0.completionAt <= windowEnd }

    let runtimes = tasksInWindow.map { max(0, $0.end - $0.start) }
    let responseTimes = responsesInWindow.map { max(0, $0.responseSeconds) }

    let windowHours = max(0.0, (windowEnd - windowStart) / 3600)
    let throughputPerHour = windowHours > 0 ? Double(tasksInWindow.count) / windowHours : 0
    let supplyRate = windowHours > 0 ? Double(assignmentsInWindow.count) / windowHours : 0

    let medianRuntime = percentile(values: runtimes, p: 0.5)
    let p90Runtime = percentile(values: runtimes, p: 0.9)
    let medianResponse = percentile(values: responseTimes, p: 0.5)
    let p90Response = percentile(values: responseTimes, p: 0.9)
    let bottleneckIndex: Double?
    if let medianRuntime, let medianResponse, medianRuntime > 0 {
        bottleneckIndex = medianResponse / medianRuntime
    } else {
        bottleneckIndex = nil
    }
    let fragmentation: Double?
    if tasksInWindow.isEmpty {
        fragmentation = nil
    } else {
        let avgPrompts = tasksInWindow.map { Double($0.prompts) }.reduce(0, +) / Double(tasksInWindow.count)
        fragmentation = avgPrompts
    }
    let reworkRate: Double?
    if tasksInWindow.isEmpty {
        reworkRate = nil
    } else {
        reworkRate = Double(reworksInWindow.count) / Double(tasksInWindow.count)
    }

    let responseHistogram = buildHistogram(values: responseTimes)

    return MetricsWindow(
        windowStart: windowStart,
        windowEnd: windowEnd,
        runningSeconds: runningSeconds,
        totalSeconds: totalSeconds,
        activeUtilization: activeUtilization,
        idleOverThreshold: idleOverThreshold,
        idleOverThresholdMinutes: idleMinutes,
        throughputPerHour: throughputPerHour,
        taskSupplyRate: supplyRate,
        tasksCompleted: tasksInWindow.count,
        assignments: assignmentsInWindow.count,
        responseSamples: responsesInWindow.count,
        runtime: MetricsRuntime(median: medianRuntime, p90: p90Runtime),
        responseTime: MetricsRuntime(median: medianResponse, p90: p90Response),
        responseHistogram: responseHistogram,
        bottleneckIndex: bottleneckIndex,
        reworkRate: reworkRate,
        fragmentation: fragmentation,
        longTailRuntime: p90Runtime
    )
}

private func computeCurrentCounts(sessions: [MetricsSession], now: Date) -> MetricsCurrent {
    let cutoff = now.addingTimeInterval(-24 * 60 * 60).timeIntervalSince1970
    var running = 0
    var idle = 0
    var total = 0
    for session in sessions {
        guard let last = session.events.last else { continue }
        if last.t < cutoff { continue }
        total += 1
        if last.kind == .user {
            running += 1
        } else {
            idle += 1
        }
    }
    let utilization = total > 0 ? Double(running) / Double(total) : 0
    return MetricsCurrent(running: running, idle: idle, total: total, utilization: utilization)
}

private func computeSegments(events: [MetricsEvent], windowStart: TimeInterval, windowEnd: TimeInterval) -> [Segment] {
    var segments: [Segment] = []
    var state: MetricsEventKind?
    var cursor = windowStart

    for event in events {
        if event.t < windowStart {
            state = event.kind
            cursor = windowStart
            continue
        }
        if event.t > windowEnd {
            break
        }
        if let state, event.t > cursor {
            segments.append(Segment(start: cursor, end: event.t, state: state))
        }
        state = event.kind
        cursor = event.t
    }

    if let state, cursor < windowEnd {
        segments.append(Segment(start: cursor, end: windowEnd, state: state))
    }

    return segments
}

private func computeTimeseries(
    segmentsBySession: [[Segment]],
    windowStart: TimeInterval,
    windowEnd: TimeInterval,
    stepSeconds: Int
) -> [MetricsTimeseriesPoint] {
    let step = max(15, min(stepSeconds, 3600))
    let steps = max(1, Int(ceil((windowEnd - windowStart) / Double(step))))
    var running = Array(repeating: 0, count: steps)
    var total = Array(repeating: 0, count: steps)

    for segments in segmentsBySession {
        for segment in segments {
            let startIndex = max(0, Int(floor((segment.start - windowStart) / Double(step))))
            let endIndex = min(steps, Int(ceil((segment.end - windowStart) / Double(step))))
            if startIndex >= endIndex { continue }
            for index in startIndex..<endIndex {
                total[index] += 1
                if segment.state == .user {
                    running[index] += 1
                }
            }
        }
    }

    var points: [MetricsTimeseriesPoint] = []
    points.reserveCapacity(steps)
    for index in 0..<steps {
        let totalCount = total[index]
        let runningCount = running[index]
        let utilization = totalCount > 0 ? Double(runningCount) / Double(totalCount) : 0
        points.append(MetricsTimeseriesPoint(
            t: windowStart + Double(index * step),
            running: runningCount,
            total: totalCount,
            utilization: utilization
        ))
    }
    return points
}

private func buildHistogram(values: [TimeInterval]) -> MetricsHistogram {
    let buckets = MetricsConstants.histogramBuckets
    var counts = Array(repeating: 0, count: buckets.count)
    for value in values {
        let minutes = value / 60.0
        var index = buckets.count - 1
        for (idx, bucket) in buckets.enumerated() {
            if minutes <= Double(bucket) {
                index = idx
                break
            }
        }
        counts[index] += 1
    }
    return MetricsHistogram(buckets: buckets, counts: counts)
}

private func percentile(values: [TimeInterval], p: Double) -> Double? {
    guard !values.isEmpty else { return nil }
    let sorted = values.sorted()
    let index = (Double(sorted.count) - 1) * p
    let lower = Int(floor(index))
    let upper = Int(ceil(index))
    if lower == upper {
        return sorted[lower]
    }
    let weight = index - Double(lower)
    return sorted[lower] * (1 - weight) + sorted[upper] * weight
}

private func isSimilarText(_ lhs: String?, _ rhs: String?) -> Bool {
    let tokensA = tokenize(lhs)
    let tokensB = tokenize(rhs)
    if tokensA.isEmpty || tokensB.isEmpty { return false }
    let overlap = tokensA.intersection(tokensB).count
    let minSize = min(tokensA.count, tokensB.count)
    return overlap >= 3 || Double(overlap) / Double(minSize) >= 0.4
}

private func tokenize(_ text: String?) -> Set<String> {
    guard let text else { return [] }
    let cleaned = text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).joined(separator: " ")
    let parts = cleaned.split(whereSeparator: \.isWhitespace)
    var tokens: Set<String> = []
    for part in parts {
        if part.count > 2 {
            tokens.insert(String(part))
        }
    }
    return tokens
}

private func parseSessionInstructions(from line: String?) -> String? {
    guard let line,
          let data = line.data(using: .utf8),
          let meta = try? JSONDecoder().decode(SessionMetaEnvelope.self, from: data),
          meta.type == "session_meta" else {
        return nil
    }
    return meta.payload?.instructions
}

private func classify(event: CodexEvent, sessionInstructions: String?) -> MetricsEvent? {
    guard let timestamp = event.timestamp,
          let date = parseTimestamp(timestamp) else {
        return nil
    }
    let payload = event.payload
    if event.type == "compacted" {
        return MetricsEvent(t: date.timeIntervalSince1970, kind: .assistant, text: nil)
    }
    if event.type == "event_msg" {
        if payload?.type == "context_compacted" {
            return MetricsEvent(t: date.timeIntervalSince1970, kind: .assistant, text: nil)
        }
        if payload?.type == "user_message" {
            if let text = userMessageText(event: event), !isIgnoredUserText(text, sessionInstructions: sessionInstructions) {
                return MetricsEvent(t: date.timeIntervalSince1970, kind: .user, text: text)
            }
            return nil
        }
        if payload?.type == "agent_message" || payload?.type == "assistant_message" {
            return MetricsEvent(t: date.timeIntervalSince1970, kind: .assistant, text: nil)
        }
    }
    if event.type == "response_item", let payload,
       payload.type == "message", let role = payload.role {
        if role == "user" {
            if let text = userMessageText(event: event), !isIgnoredUserText(text, sessionInstructions: sessionInstructions) {
                return MetricsEvent(t: date.timeIntervalSince1970, kind: .user, text: text)
            }
            return nil
        }
        if role == "assistant" {
            return MetricsEvent(t: date.timeIntervalSince1970, kind: .assistant, text: nil)
        }
    }
    return nil
}

private func userMessageText(event: CodexEvent) -> String? {
    guard let payload = event.payload else { return nil }
    if event.type == "event_msg", payload.type == "user_message" {
        return payload.message ?? payload.instructions
    }
    if event.type == "response_item", payload.type == "message", payload.role == "user" {
        let parts = payload.content?.compactMap { $0.text } ?? []
        if !parts.isEmpty {
            return parts.joined(separator: "\n")
        }
        return payload.instructions
    }
    return nil
}

private func isIgnoredUserText(_ text: String, sessionInstructions: String?) -> Bool {
    if isBootstrapUserText(text, sessionInstructions: sessionInstructions) {
        return true
    }
    return isShellCommandUserText(text)
}

private func isShellCommandUserText(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.hasPrefix("!") || trimmed.hasPrefix("<user_shell_command>")
}

private func isBootstrapUserText(_ text: String, sessionInstructions: String?) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return true }
    if trimmed.hasPrefix("<environment_context>") { return true }
    if trimmed.hasPrefix("<user_instructions>") { return true }
    if let sessionInstructions, !sessionInstructions.isEmpty, trimmed.contains(sessionInstructions) {
        return true
    }
    return false
}

private func isoString(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: date)
}

private let isoFormatterFractional: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

private let isoFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
}()

private func parseTimestamp(_ raw: String) -> Date? {
    if let date = isoFormatterFractional.date(from: raw) {
        return date
    }
    return isoFormatter.date(from: raw)
}

private struct SessionMetaEnvelope: Decodable {
    let type: String
    let payload: SessionMetaPayload?
}

private struct SessionMetaPayload: Decodable {
    let instructions: String?
}

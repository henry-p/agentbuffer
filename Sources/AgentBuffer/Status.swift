import Foundation

final class StatusReader {
    private let providers: [AgentProvider]

    init(providers: [AgentProvider] = AgentProviderRegistry.defaultProviders()) {
        self.providers = providers
    }

    convenience init(
        codexSessionsURL: URL = CodexSessionReader.defaultBaseURL(),
        claudeSessionsURL: URL = ClaudeSessionReader.defaultBaseURL()
    ) {
        self.init(providers: AgentProviderRegistry.defaultProviders(
            codexSessionsURL: codexSessionsURL,
            claudeSessionsURL: claudeSessionsURL
        ))
    }

    func readSnapshot() -> StatusSnapshot {
        var states: [AgentState] = []
        for provider in providers {
            let providerStates = provider.readStates()
            states.append(contentsOf: providerStates)
            states.append(contentsOf: placeholderStates(for: provider, from: providerStates))
        }
        return StatusEvaluator.evaluate(states: states)
    }

    func currentPids() -> [Int] {
        providers.flatMap { $0.currentPids() }
    }

    var sessionRoots: [URL] {
        providers.flatMap { $0.sessionRoots }
    }

    private func placeholderStates(for provider: AgentProvider, from states: [AgentState]) -> [AgentState] {
        let knownPids = Set(states.compactMap { $0.pid })
        let missingPids = provider.currentPids().filter { !knownPids.contains($0) }
        guard !missingPids.isEmpty else {
            return []
        }
        return missingPids.map { pid in
            AgentState(
                id: "pid-\(pid)",
                state: .finished,
                finishedAt: nil,
                lastUserAt: nil,
                agentType: provider.type,
                lastUserMessage: nil,
                pid: pid
            )
        }
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

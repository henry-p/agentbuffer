import Foundation

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

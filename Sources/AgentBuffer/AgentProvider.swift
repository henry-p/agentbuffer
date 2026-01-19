import Foundation

protocol AgentProvider {
    var type: AgentType { get }
    var baseURL: URL { get }
    var sessionRoots: [URL] { get }
    func readStates() -> [AgentState]
    func currentPids() -> [Int]
}

struct AgentProviderRegistry {
    static func defaultProviders(
        codexSessionsURL: URL = CodexSessionReader.defaultBaseURL(),
        claudeSessionsURL: URL = ClaudeSessionReader.defaultBaseURL()
    ) -> [AgentProvider] {
        [
            CodexSessionReader(baseURL: codexSessionsURL),
            ClaudeSessionReader(baseURL: claudeSessionsURL)
        ]
    }
}

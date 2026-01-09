import Foundation

final class SingleInstanceLock {
    private let lockURL: URL
    private let pid: Int32

    init?(name: String) {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let baseURL = appSupport?.appendingPathComponent("AgentBuffer", isDirectory: true)
        self.lockURL = baseURL?.appendingPathComponent("\(name).lock") ?? URL(fileURLWithPath: "/tmp/\(name).lock")
        self.pid = ProcessInfo.processInfo.processIdentifier

        if let baseURL {
            try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        }

        if FileManager.default.fileExists(atPath: lockURL.path) {
            if let existing = readPid(), isProcessAlive(existing) {
                return nil
            }
            try? FileManager.default.removeItem(at: lockURL)
        }

        let pidString = "\(pid)\n"
        do {
            try pidString.write(to: lockURL, atomically: true, encoding: .utf8)
        } catch {
            return nil
        }
    }

    func release() {
        if let existing = readPid(), existing == pid {
            try? FileManager.default.removeItem(at: lockURL)
        }
    }

    private func readPid() -> Int32? {
        guard let data = try? Data(contentsOf: lockURL),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return Int32(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func isProcessAlive(_ pid: Int32) -> Bool {
        if pid <= 0 {
            return false
        }
        return kill(pid, 0) == 0
    }
}

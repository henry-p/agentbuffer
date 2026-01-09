import AppKit
import Foundation

final class TerminalNavigator {
    func focus(pid: Int) -> Bool {
        guard let tty = ttyForPid(pid) else {
            return false
        }
        let shortTTY = tty.hasPrefix("/dev/") ? String(tty.dropFirst(5)) : tty
        let fullTTY = tty.hasPrefix("/dev/") ? tty : "/dev/\(tty)"

        let runningApps = NSWorkspace.shared.runningApplications
        if runningApps.contains(where: { $0.bundleIdentifier == "com.googlecode.iterm2" }) {
            if focusIterm2(fullTTY: fullTTY, shortTTY: shortTTY) {
                return true
            }
        }
        if runningApps.contains(where: { $0.bundleIdentifier == "com.apple.Terminal" }) {
            if focusTerminal(fullTTY: fullTTY, shortTTY: shortTTY) {
                return true
            }
        }
        return false
    }

    private func ttyForPid(_ pid: Int) -> String? {
        guard let output = runCommand("/bin/ps", arguments: ["-o", "tty=", "-p", String(pid)]) else {
            return nil
        }
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "??" else {
            return nil
        }
        return trimmed
    }

    private func focusIterm2(fullTTY: String, shortTTY: String) -> Bool {
        let script = """
        tell application \"iTerm2\"
            set targetTTY to \"\(escapeAppleScript(fullTTY))\"
            set shortTTY to \"\(escapeAppleScript(shortTTY))\"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        set sessionTTY to (tty of s)
                        if sessionTTY contains targetTTY or sessionTTY contains shortTTY then
                            select t
                            select s
                            activate
                            return true
                        end if
                    end repeat
                end repeat
            end repeat
            return false
        end tell
        """
        return runAppleScriptReturningBool(script)
    }

    private func focusTerminal(fullTTY: String, shortTTY: String) -> Bool {
        let script = """
        tell application \"Terminal\"
            set targetTTY to \"\(escapeAppleScript(fullTTY))\"
            set shortTTY to \"\(escapeAppleScript(shortTTY))\"
            repeat with w in windows
                repeat with t in tabs of w
                    set tabTTY to (tty of t)
                    if tabTTY contains targetTTY or tabTTY contains shortTTY then
                        set index of w to 1
                        activate
                        return true
                    end if
                end repeat
            end repeat
            return false
        end tell
        """
        return runAppleScriptReturningBool(script)
    }

    private func runAppleScriptReturningBool(_ source: String) -> Bool {
        guard let script = NSAppleScript(source: source) else {
            return false
        }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error, Settings.devModeEnabled {
            NSLog("[AgentBuffer] AppleScript error: %@", String(describing: error))
        }
        return result.booleanValue
    }

    private func escapeAppleScript(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func runCommand(_ path: String, arguments: [String]) -> String? {
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
}

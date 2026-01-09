import Dispatch
import Foundation
import Darwin

private enum FileWatcherConstants {
    static let invalidDescriptor: Int32 = -1
    static let maxWatchedDayDirectories = 250
    static let yearComponentLength = 4
    static let monthComponentLength = 2
    static let dayComponentLength = 2
}

final class FileWatcher {
    private let rootURL: URL
    private let queue: DispatchQueue
    private let onChange: () -> Void

    private var parentSource: DispatchSourceFileSystemObject?
    private var parentDescriptor: Int32 = FileWatcherConstants.invalidDescriptor
    private var parentURL: URL?

    private var directorySources: [URL: DispatchSourceFileSystemObject] = [:]
    private var directoryDescriptors: [URL: Int32] = [:]

    var isWatching: Bool {
        parentSource != nil || !directorySources.isEmpty
    }

    init(url: URL, queue: DispatchQueue = DispatchQueue(label: "AgentBuffer.FileWatcher"), onChange: @escaping () -> Void) {
        self.rootURL = url
        self.queue = queue
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    func start() {
        startParentWatcher()
        startDirectoryTreeWatcher()
    }

    func stop() {
        stopDirectoryTreeWatcher()
        stopParentWatcher()
    }

    private func startParentWatcher(force: Bool = false) {
        if !force, parentSource != nil {
            return
        }
        let preferredParent = rootURL.deletingLastPathComponent()
        let targetParent = nearestExistingDirectory(for: preferredParent, stopAt: preferredParent)
        guard let targetParent else {
            return
        }
        if parentURL != targetParent {
            stopParentWatcher()
        }
        parentURL = targetParent
        parentDescriptor = open(targetParent.path, O_EVTONLY)
        guard parentDescriptor >= 0 else {
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: parentDescriptor,
            eventMask: [.write, .rename, .delete, .revoke],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            guard let self else {
                return
            }
            let flags = source.data
            if flags.contains(.delete) || flags.contains(.rename) || flags.contains(.revoke) {
                self.stopParentWatcher()
            }
            self.startParentWatcher(force: true)
            self.startDirectoryTreeWatcher()
            self.onChange()
        }
        source.setCancelHandler { [weak self] in
            guard let self else {
                return
            }
            if self.parentDescriptor >= 0 {
                close(self.parentDescriptor)
                self.parentDescriptor = FileWatcherConstants.invalidDescriptor
            }
        }
        parentSource = source
        source.resume()
    }

    private func startDirectoryTreeWatcher() {
        guard FileManager.default.fileExists(atPath: rootURL.path) else {
            stopDirectoryTreeWatcher()
            return
        }
        let desiredDirectories = desiredWatchDirectories()
        let desiredSet = Set(desiredDirectories.map { $0.standardizedFileURL })

        for directory in desiredSet where directorySources[directory] == nil {
            addDirectoryWatcher(for: directory)
        }

        for directory in directorySources.keys where !desiredSet.contains(directory) {
            removeDirectoryWatcher(for: directory)
        }
    }

    private func addDirectoryWatcher(for url: URL) {
        let normalized = url.standardizedFileURL
        let descriptor = open(normalized.path, O_EVTONLY)
        guard descriptor >= 0 else {
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .attrib, .rename, .delete, .revoke],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            guard let self else {
                return
            }
            let flags = source.data
            if flags.contains(.delete) || flags.contains(.rename) || flags.contains(.revoke) {
                self.removeDirectoryWatcher(for: normalized)
            }
            self.startDirectoryTreeWatcher()
            self.onChange()
        }
        source.setCancelHandler { [weak self] in
            guard let self else {
                return
            }
            if let existing = self.directoryDescriptors[normalized], existing >= 0 {
                close(existing)
            }
            self.directoryDescriptors[normalized] = nil
        }
        directoryDescriptors[normalized] = descriptor
        directorySources[normalized] = source
        source.resume()
    }

    private func removeDirectoryWatcher(for url: URL) {
        let normalized = url.standardizedFileURL
        directorySources[normalized]?.cancel()
        directorySources[normalized] = nil
        if let descriptor = directoryDescriptors[normalized], descriptor >= 0 {
            close(descriptor)
        }
        directoryDescriptors[normalized] = nil
    }

    private func stopDirectoryTreeWatcher() {
        for (url, source) in directorySources {
            source.cancel()
            if let descriptor = directoryDescriptors[url], descriptor >= 0 {
                close(descriptor)
            }
        }
        directorySources.removeAll()
        directoryDescriptors.removeAll()
    }

    private func stopParentWatcher() {
        parentSource?.cancel()
        parentSource = nil
        parentURL = nil
    }

    private func nearestExistingDirectory(for url: URL, stopAt: URL) -> URL? {
        var current = url
        while true {
            if FileManager.default.fileExists(atPath: current.path) {
                return current
            }
            if current.path == stopAt.path {
                return nil
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path {
                return nil
            }
            current = parent
        }
    }

    private func desiredWatchDirectories() -> [URL] {
        let entries = collectDayEntries(under: rootURL).sorted { $0.date > $1.date }
        var desired: [URL] = []
        var desiredSet = Set<URL>()

        func appendIfNeeded(_ url: URL) {
            let normalized = url.standardizedFileURL
            guard !desiredSet.contains(normalized) else {
                return
            }
            desiredSet.insert(normalized)
            desired.append(normalized)
        }

        appendIfNeeded(rootURL)

        for entry in entries.prefix(FileWatcherConstants.maxWatchedDayDirectories) {
            appendIfNeeded(entry.dayURL)
            appendIfNeeded(entry.monthURL)
            appendIfNeeded(entry.yearURL)
        }

        return desired
    }

    private struct DayEntry {
        let date: Date
        let yearURL: URL
        let monthURL: URL
        let dayURL: URL
    }

    private func collectDayEntries(under root: URL) -> [DayEntry] {
        let fileManager = FileManager.default
        var results: [DayEntry] = []
        let calendar = Calendar(identifier: .gregorian)

        let yearDirectories = directoryChildren(of: root, fileManager: fileManager)
        for yearURL in yearDirectories {
            let yearComponent = yearURL.lastPathComponent
            guard let year = Int(yearComponent), yearComponent.count == FileWatcherConstants.yearComponentLength else {
                continue
            }
            let monthDirectories = directoryChildren(of: yearURL, fileManager: fileManager)
            for monthURL in monthDirectories {
                let monthComponent = monthURL.lastPathComponent
                guard let month = Int(monthComponent), monthComponent.count == FileWatcherConstants.monthComponentLength else {
                    continue
                }
                let dayDirectories = directoryChildren(of: monthURL, fileManager: fileManager)
                for dayURL in dayDirectories {
                    let dayComponent = dayURL.lastPathComponent
                    guard let day = Int(dayComponent), dayComponent.count == FileWatcherConstants.dayComponentLength else {
                        continue
                    }
                    var components = DateComponents()
                    components.year = year
                    components.month = month
                    components.day = day
                    guard let date = calendar.date(from: components) else {
                        continue
                    }
                    results.append(DayEntry(date: date, yearURL: yearURL, monthURL: monthURL, dayURL: dayURL))
                }
            }
        }

        return results
    }

    private func directoryChildren(of url: URL, fileManager: FileManager) -> [URL] {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return contents.filter { isDirectory($0) }
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }
}

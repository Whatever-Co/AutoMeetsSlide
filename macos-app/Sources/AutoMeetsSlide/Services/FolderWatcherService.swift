import AppKit
import CoreServices

/// Service for monitoring a folder for new m4a files
@MainActor
@Observable
class FolderWatcherService {
    static let shared = FolderWatcherService()

    private(set) var isWatching: Bool = false

    var watchedFolderPath: String? {
        didSet {
            UserDefaults.standard.set(watchedFolderPath, forKey: "watchedFolderPath")
        }
    }

    private var knownFiles: Set<String> {
        get {
            Set(UserDefaults.standard.stringArray(forKey: "knownWatchedFiles") ?? [])
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: "knownWatchedFiles")
        }
    }

    private var eventStream: FSEventStreamRef?
    private let fileManager = FileManager.default

    private init() {
        watchedFolderPath = UserDefaults.standard.string(forKey: "watchedFolderPath")
    }

    // MARK: - Folder Selection

    func selectFolder() async {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Watch"
        panel.message = "Select a folder to watch for new M4A files"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        watchedFolderPath = url.path
        startWatching()
    }

    func clearWatchedFolder() {
        stopWatching()
        watchedFolderPath = nil
        knownFiles = []
    }

    // MARK: - FSEvents Monitoring

    func startWatching() {
        guard let path = watchedFolderPath,
              fileManager.fileExists(atPath: path) else {
            Log.watcher.info("No valid watched folder path")
            return
        }

        stopWatching()

        // Need to use nonisolated callback, so we capture self weakly
        let unmanagedSelf = Unmanaged.passUnretained(self)
        var context = FSEventStreamContext(
            version: 0,
            info: unmanagedSelf.toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, info, numEvents, eventPaths, _, _ in
            guard let info = info else { return }
            let watcher = Unmanaged<FolderWatcherService>.fromOpaque(info).takeUnretainedValue()

            let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as! [String]

            Task { @MainActor in
                watcher.handleFSEvents(paths: paths)
            }
        }

        let pathsToWatch = [path] as CFArray

        eventStream = FSEventStreamCreate(
            nil,
            callback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        )

        guard let stream = eventStream else {
            Log.watcher.error("Failed to create FSEventStream")
            return
        }

        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)

        isWatching = true
        Log.watcher.info("Started watching: \(path)")

        markExistingFilesAsKnown()
    }

    func stopWatching() {
        guard let stream = eventStream else { return }

        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        eventStream = nil
        isWatching = false

        Log.watcher.info("Stopped watching")
    }

    // MARK: - Event Handling

    private func handleFSEvents(paths: [String]) {
        Log.watcher.debug("FSEvent paths: \(paths)")

        for path in paths {
            let url = URL(fileURLWithPath: path)

            guard url.pathExtension.lowercased() == "m4a" else { continue }
            guard fileManager.fileExists(atPath: path) else { continue }
            guard !knownFiles.contains(path) else {
                Log.watcher.debug("Already known: \(path)")
                continue
            }

            // Wait for file to be fully written
            Task {
                try? await Task.sleep(for: .seconds(1))
                self.addFileToQueue(url: url)
            }
        }
    }

    /// Mark existing files as known so they won't be processed.
    /// Only newly added files after this point will be queued.
    private func markExistingFilesAsKnown() {
        guard let path = watchedFolderPath else { return }

        let url = URL(fileURLWithPath: path)
        guard let contents = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let m4aFiles = contents.filter { $0.pathExtension.lowercased() == "m4a" }

        var known = knownFiles
        for fileURL in m4aFiles {
            known.insert(fileURL.path)
        }
        knownFiles = known

        Log.watcher.info("Marked \(m4aFiles.count) existing files as known")
    }

    private func addFileToQueue(url: URL) {
        Log.watcher.info("Adding to queue from watched folder: \(url.lastPathComponent)")

        var known = knownFiles
        known.insert(url.path)
        knownFiles = known

        AppState.shared.addFilesIfNotExists([url])
    }
}

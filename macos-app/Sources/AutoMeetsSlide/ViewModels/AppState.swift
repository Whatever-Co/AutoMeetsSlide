import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Main application state
@MainActor
@Observable
class AppState {
    static let shared = AppState()

    // Auth state
    var isAuthenticated: Bool? = nil  // nil = checking
    var isCheckingAuth: Bool = false

    // File queue
    var files: [FileItem] = []
    var currentProcessingId: UUID? = nil

    // UI state
    var currentStatus: String = "Ready"
    var showLoginWebView: Bool = false

    // Services
    let sidecarManager = SidecarManager()

    // Settings (persisted to UserDefaults)
    static let defaultSystemPrompt = "この内容から包括的なスライドデッキを日本語で作成してください。"

    var systemPrompt: String = AppState.defaultSystemPrompt {
        didSet {
            UserDefaults.standard.set(systemPrompt, forKey: "systemPrompt")
        }
    }

    var downloadFolder: String = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path ?? "" {
        didSet {
            UserDefaults.standard.set(downloadFolder, forKey: "downloadFolder")
        }
    }

    // Queue persistence
    private static let queueFileURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let appDir = appSupport.appendingPathComponent("AutoMeetsSlide")
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("queue.json")
    }()

    private init() {
        // Load persisted settings
        if let savedPrompt = UserDefaults.standard.string(forKey: "systemPrompt") {
            systemPrompt = savedPrompt
        }
        if let savedFolder = UserDefaults.standard.string(forKey: "downloadFolder") {
            downloadFolder = savedFolder
        }
        loadQueue()
    }

    // MARK: - Authentication

    func checkAuth() async {
        isCheckingAuth = true
        defer { isCheckingAuth = false }

        Log.auth.info("checkAuth started")

        // First, try to authenticate using Safari cookies if no valid storage state
        if !AuthService.hasValidStorageState() {
            Log.auth.info("No valid storage state, trying silent auth with Safari cookies...")
            let authenticated = await AuthService.tryAuthenticateWithSafariCookies()
            if authenticated {
                Log.auth.info("Successfully authenticated with Safari cookies")
            } else {
                Log.auth.info("Silent auth failed, will show login button")
            }
        } else {
            Log.auth.info("Valid storage state exists, skipping silent auth")
        }

        // Now verify with sidecar
        do {
            Log.auth.info("Running sidecar check-auth...")
            let response = try await sidecarManager.run(.checkAuth)
            let authenticated = response?.authenticated ?? false
            Log.auth.info("Sidecar auth result: \(authenticated)")
            isAuthenticated = authenticated
        } catch {
            Log.auth.error("Auth check failed: \(error.localizedDescription)")
            isAuthenticated = false
        }
    }

    func logout() {
        AuthService.clearStorageState()
        isAuthenticated = false
    }

    // MARK: - File Queue

    func selectFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            .mp3, .wav, .mpeg4Audio,
            .pdf, .plainText,
            UTType(filenameExtension: "docx")!
        ]

        if panel.runModal() == .OK {
            addFiles(panel.urls)
        }
    }

    func addFiles(_ urls: [URL]) {
        let newItems = urls.compactMap { url -> FileItem? in
            guard SupportedFileType.isSupported(url) else { return nil }
            return FileItem(url: url)
        }
        files.append(contentsOf: newItems)
        saveQueue()
    }

    func addFilesIfNotExists(_ urls: [URL]) {
        let existingPaths = Set(files.map { $0.path })
        let newUrls = urls.filter { !existingPaths.contains($0.path) }
        addFiles(newUrls)
    }

    func removeFile(_ id: UUID) {
        files.removeAll { $0.id == id }
        saveQueue()
    }

    func updateFileStatus(_ id: UUID, status: ProcessingStatus, outputPath: String? = nil, error: String? = nil) {
        guard let index = files.firstIndex(where: { $0.id == id }) else { return }
        files[index].status = status
        files[index].outputPath = outputPath
        files[index].error = error
        saveQueue()
    }

    func clearCompleted() {
        files.removeAll { $0.status == .completed }
        saveQueue()
    }

    // MARK: - Queue Persistence

    private func saveQueue() {
        let itemsToSave = files.filter { $0.status == .pending || $0.status == .processing || $0.status == .restoring }
        do {
            let data = try JSONEncoder().encode(itemsToSave)
            try data.write(to: Self.queueFileURL, options: .atomic)
        } catch {
            Log.general.error("Failed to save queue: \(error.localizedDescription)")
        }
    }

    private func loadQueue() {
        guard FileManager.default.fileExists(atPath: Self.queueFileURL.path) else { return }
        do {
            let data = try Data(contentsOf: Self.queueFileURL)
            let items = try JSONDecoder().decode([FileItem].self, from: data)
            files = items
            Log.general.info("Loaded \(items.count) items from queue")
        } catch {
            Log.general.error("Failed to load queue: \(error.localizedDescription)")
        }
    }

    // MARK: - Processing

    func processNextFile() async {
        guard currentProcessingId == nil,
              let nextFile = files.first(where: { $0.status == .pending })
        else {
            return
        }

        currentProcessingId = nextFile.id
        updateFileStatus(nextFile.id, status: .processing)

        do {
            let response = try await sidecarManager.run(
                .process(
                    filePath: nextFile.path,
                    outputDir: downloadFolder,
                    systemPrompt: systemPrompt,
                    jobId: nextFile.id.uuidString
                )
            )

            if let outputPath = response?.outputPath {
                updateFileStatus(nextFile.id, status: .completed, outputPath: outputPath)
                NotificationManager.shared.notifyCompletion(fileName: nextFile.name, outputPath: outputPath)
            } else if let error = response?.error {
                updateFileStatus(nextFile.id, status: .error, error: error)
                NotificationManager.shared.notifyError(fileName: nextFile.name, error: error)
            } else {
                updateFileStatus(nextFile.id, status: .error, error: "Unknown error")
                NotificationManager.shared.notifyError(fileName: nextFile.name, error: "Unknown error")
            }
        } catch {
            updateFileStatus(nextFile.id, status: .error, error: error.localizedDescription)
            NotificationManager.shared.notifyError(fileName: nextFile.name, error: error.localizedDescription)
        }

        currentProcessingId = nil
    }

    // MARK: - Restoration

    func restoreInProgressItems() async {
        let itemsToRestore = files.filter { $0.status == .processing || $0.status == .restoring }
        guard !itemsToRestore.isEmpty else { return }

        Log.general.info("Restoring \(itemsToRestore.count) in-progress items")

        for item in itemsToRestore {
            updateFileStatus(item.id, status: .restoring)
            currentProcessingId = item.id

            do {
                // Search NotebookLM for a notebook matching this item's UUID
                let findResponse = try await sidecarManager.run(
                    .findNotebook(jobId: item.id.uuidString)
                )

                guard let notebookId = findResponse?.notebookId else {
                    // No notebook found - requeue for processing from scratch
                    Log.general.info("No notebook found for \(item.name), requeuing as pending")
                    updateFileStatus(item.id, status: .pending)
                    currentProcessingId = nil
                    continue
                }

                let taskId = findResponse?.taskId
                let genStatus = findResponse?.generationStatus

                Log.general.info("Found notebook \(notebookId) for \(item.name), status=\(genStatus ?? "unknown")")

                if genStatus == "completed" {
                    try await downloadAndComplete(item: item, notebookId: notebookId)
                } else if genStatus == "failed" {
                    updateFileStatus(item.id, status: .error, error: "Generation failed on NotebookLM")
                } else if genStatus == "no_artifact" {
                    // Notebook exists but generation hasn't started - requeue
                    Log.general.info("No artifact for \(item.name), requeuing as pending")
                    updateFileStatus(item.id, status: .pending)
                } else if let taskId {
                    // Still processing - poll until done
                    updateFileStatus(item.id, status: .processing)
                    try await pollUntilComplete(item: item, notebookId: notebookId, taskId: taskId)
                } else {
                    updateFileStatus(item.id, status: .pending)
                }
            } catch {
                updateFileStatus(item.id, status: .error, error: "Restore failed: \(error.localizedDescription)")
            }

            currentProcessingId = nil
        }
    }

    private func downloadAndComplete(item: FileItem, notebookId: String) async throws {
        let fileNameStem = URL(fileURLWithPath: item.path).deletingPathExtension().lastPathComponent
        let downloadResponse = try await sidecarManager.run(
            .download(notebookId: notebookId, outputDir: downloadFolder, fileNameStem: fileNameStem)
        )
        if let outputPath = downloadResponse?.outputPath {
            updateFileStatus(item.id, status: .completed, outputPath: outputPath)
            NotificationManager.shared.notifyCompletion(fileName: item.name, outputPath: outputPath)
        } else if let error = downloadResponse?.error {
            updateFileStatus(item.id, status: .error, error: error)
        } else {
            updateFileStatus(item.id, status: .error, error: "Download failed")
        }
    }

    private func pollUntilComplete(item: FileItem, notebookId: String, taskId: String) async throws {
        let maxAttempts = 60  // 30 minutes with 30s intervals

        for _ in 0..<maxAttempts {
            try await Task.sleep(for: .seconds(30))

            let response = try await sidecarManager.run(
                .checkStatus(notebookId: notebookId, taskId: taskId)
            )

            if response?.isComplete == true {
                try await downloadAndComplete(item: item, notebookId: notebookId)
                return
            }
            if response?.isFailed == true {
                updateFileStatus(item.id, status: .error, error: "Generation failed on NotebookLM")
                return
            }
        }

        updateFileStatus(item.id, status: .error, error: "Generation timed out")
    }
}

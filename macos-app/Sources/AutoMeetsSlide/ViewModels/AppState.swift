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
    var processingIds: Set<UUID> = []

    // Concurrency
    var maxConcurrency: Int = 3 {
        didSet {
            UserDefaults.standard.set(maxConcurrency, forKey: "maxConcurrency")
        }
    }

    var isProcessing: Bool { !processingIds.isEmpty }
    var activeProcessingCount: Int { processingIds.count }

    // UI state
    var showLoginWebView: Bool = false
    var pendingDroppedFiles: [URL]? = nil

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

    var autoDeleteNotebook: Bool = false {
        didSet {
            UserDefaults.standard.set(autoDeleteNotebook, forKey: "autoDeleteNotebook")
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
        let savedConcurrency = UserDefaults.standard.integer(forKey: "maxConcurrency")
        if savedConcurrency > 0 {
            maxConcurrency = savedConcurrency
        }
        autoDeleteNotebook = UserDefaults.standard.bool(forKey: "autoDeleteNotebook")
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

    /// Open file picker and show the settings sheet for the selected files
    func selectFilesForSettingsSheet() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            .mp3, .wav, .mpeg4Audio,
            .pdf, .plainText,
            UTType(filenameExtension: "docx")!
        ]

        if panel.runModal() == .OK {
            let supported = panel.urls.filter { SupportedFileType.isSupported($0) }
            if !supported.isEmpty {
                pendingDroppedFiles = supported
            }
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

    /// Add a job with multiple sources and a custom prompt
    func addJob(files fileURLs: [URL], sourceURLs: [String], customPrompt: String, deleteNotebook: Bool) {
        guard let primaryURL = fileURLs.first else {
            // URL-only job not supported yet
            return
        }

        var item = FileItem(url: primaryURL)
        item.additionalPaths = fileURLs.dropFirst().map(\.path)
        item.sourceURLs = sourceURLs
        // Only store custom prompt if it differs from default
        if customPrompt != Self.defaultSystemPrompt {
            item.customPrompt = customPrompt
        }
        // Only store if it differs from global default
        if deleteNotebook != autoDeleteNotebook {
            item.deleteNotebook = deleteNotebook
        }
        files.append(item)
        saveQueue()
    }

    func addFilesIfNotExists(_ urls: [URL]) {
        let existingPaths = Set(files.map { $0.path })
        let newUrls = urls.filter { !existingPaths.contains($0.path) }
        addFiles(newUrls)
    }

    func removeFile(_ id: UUID) {
        processingIds.remove(id)
        files.removeAll { $0.id == id }
        saveQueue()
    }

    func updateFileStatus(_ id: UUID, status: ProcessingStatus, outputPath: String? = nil, notebookId: String? = nil, error: String? = nil) {
        guard let index = files.firstIndex(where: { $0.id == id }) else { return }
        files[index].status = status
        if let outputPath { files[index].outputPath = outputPath }
        if let notebookId { files[index].notebookId = notebookId }
        if let error { files[index].error = error }
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
        // Fill available slots with pending files
        while processingIds.count < maxConcurrency,
              let nextFile = files.first(where: { $0.status == .pending }) {
            processingIds.insert(nextFile.id)
            updateFileStatus(nextFile.id, status: .processing)

            let file = nextFile
            Task { [weak self] in
                guard let self else { return }
                await self.processFile(file)
            }
        }
    }

    private func processFile(_ file: FileItem) async {
        do {
            var capturedNotebookId: String?
            let effectivePrompt = file.customPrompt ?? systemPrompt
            let shouldDeleteNotebook = file.deleteNotebook ?? autoDeleteNotebook
            let response = try await sidecarManager.run(
                .process(
                    filePath: file.path,
                    outputDir: downloadFolder,
                    systemPrompt: effectivePrompt,
                    jobId: file.id.uuidString,
                    additionalFiles: file.additionalPaths,
                    sourceURLs: file.sourceURLs,
                    deleteNotebook: shouldDeleteNotebook
                )
            ) { [self] progress in
                if let nid = progress.notebookId {
                    capturedNotebookId = nid
                    updateFileStatus(file.id, status: .processing, notebookId: nid)
                }
            }

            let notebookId = response?.notebookId ?? capturedNotebookId
            if let outputPath = response?.outputPath {
                updateFileStatus(file.id, status: .completed, outputPath: outputPath, notebookId: notebookId)
                NotificationManager.shared.notifyCompletion(fileName: file.name, outputPath: outputPath)
            } else if let error = response?.error {
                updateFileStatus(file.id, status: .error, error: error)
                NotificationManager.shared.notifyError(fileName: file.name, error: error)
            } else {
                updateFileStatus(file.id, status: .error, error: "Unknown error")
                NotificationManager.shared.notifyError(fileName: file.name, error: "Unknown error")
            }
        } catch {
            updateFileStatus(file.id, status: .error, error: error.localizedDescription)
            NotificationManager.shared.notifyError(fileName: file.name, error: error.localizedDescription)
        }

        processingIds.remove(file.id)

        // Fill the freed slot
        await processNextFile()
    }

    // MARK: - Restoration

    func restoreInProgressItems() async {
        let itemsToRestore = files.filter { $0.status == .processing || $0.status == .restoring }
        guard !itemsToRestore.isEmpty else { return }

        Log.general.info("Restoring \(itemsToRestore.count) in-progress items")

        for item in itemsToRestore {
            updateFileStatus(item.id, status: .restoring)
        }

        await withTaskGroup(of: Void.self) { group in
            var activeCount = 0

            for item in itemsToRestore {
                if activeCount >= maxConcurrency {
                    await group.next()
                    activeCount -= 1
                }

                activeCount += 1
                group.addTask { [weak self] in
                    guard let self else { return }
                    await self.restoreSingleItem(item)
                }
            }

            await group.waitForAll()
        }
    }

    private func restoreSingleItem(_ item: FileItem) async {
        processingIds.insert(item.id)

        do {
            let findResponse = try await sidecarManager.run(
                .findNotebook(jobId: item.id.uuidString)
            )

            guard let notebookId = findResponse?.notebookId else {
                Log.general.info("No notebook found for \(item.name), requeuing as pending")
                updateFileStatus(item.id, status: .pending)
                processingIds.remove(item.id)
                return
            }

            let taskId = findResponse?.taskId
            let genStatus = findResponse?.generationStatus

            updateFileStatus(item.id, status: .restoring, notebookId: notebookId)

            Log.general.info("Found notebook \(notebookId) for \(item.name), status=\(genStatus ?? "unknown")")

            if genStatus == "completed" {
                try await downloadAndComplete(item: item, notebookId: notebookId)
            } else if genStatus == "failed" {
                updateFileStatus(item.id, status: .error, error: "Generation failed on NotebookLM")
            } else if genStatus == "no_artifact" {
                Log.general.info("No artifact for \(item.name), requeuing as pending")
                updateFileStatus(item.id, status: .pending)
            } else if let taskId {
                updateFileStatus(item.id, status: .processing)
                try await pollUntilComplete(item: item, notebookId: notebookId, taskId: taskId)
            } else {
                updateFileStatus(item.id, status: .pending)
            }
        } catch {
            updateFileStatus(item.id, status: .error, error: "Restore failed: \(error.localizedDescription)")
        }

        processingIds.remove(item.id)
    }

    private func downloadAndComplete(item: FileItem, notebookId: String) async throws {
        let fileNameStem = URL(fileURLWithPath: item.path).deletingPathExtension().lastPathComponent
        let downloadResponse = try await sidecarManager.run(
            .download(notebookId: notebookId, outputDir: downloadFolder, fileNameStem: fileNameStem)
        )
        if let outputPath = downloadResponse?.outputPath {
            updateFileStatus(item.id, status: .completed, outputPath: outputPath, notebookId: notebookId)
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

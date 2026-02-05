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

    private init() {
        // Load persisted settings
        if let savedPrompt = UserDefaults.standard.string(forKey: "systemPrompt") {
            systemPrompt = savedPrompt
        }
        if let savedFolder = UserDefaults.standard.string(forKey: "downloadFolder") {
            downloadFolder = savedFolder
        }
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
    }

    func addFilesIfNotExists(_ urls: [URL]) {
        let existingPaths = Set(files.map { $0.path })
        let newUrls = urls.filter { !existingPaths.contains($0.path) }
        addFiles(newUrls)
    }

    func removeFile(_ id: UUID) {
        files.removeAll { $0.id == id }
    }

    func updateFileStatus(_ id: UUID, status: ProcessingStatus, outputPath: String? = nil, error: String? = nil) {
        guard let index = files.firstIndex(where: { $0.id == id }) else { return }
        files[index].status = status
        files[index].outputPath = outputPath
        files[index].error = error
    }

    func clearCompleted() {
        files.removeAll { $0.status == .completed }
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
                    systemPrompt: systemPrompt
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
}

import Foundation
import SwiftUI

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

    // Settings
    var systemPrompt: String = "Create a comprehensive slide deck from this content in Japanese."
    var downloadFolder: String = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path ?? ""

    private init() {}

    // MARK: - Authentication

    func checkAuth() async {
        isCheckingAuth = true
        defer { isCheckingAuth = false }

        do {
            let response = try await sidecarManager.run(.checkAuth)
            isAuthenticated = response?.authenticated ?? false
        } catch {
            print("Auth check failed: \(error)")
            isAuthenticated = false
        }
    }

    func logout() {
        AuthService.clearStorageState()
        isAuthenticated = false
    }

    // MARK: - File Queue

    func addFiles(_ urls: [URL]) {
        let newItems = urls.compactMap { url -> FileItem? in
            guard SupportedFileType.isSupported(url) else { return nil }
            return FileItem(url: url)
        }
        files.append(contentsOf: newItems)
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
            } else if let error = response?.error {
                updateFileStatus(nextFile.id, status: .error, error: error)
            } else {
                updateFileStatus(nextFile.id, status: .error, error: "Unknown error")
            }
        } catch {
            updateFileStatus(nextFile.id, status: .error, error: error.localizedDescription)
        }

        currentProcessingId = nil
    }
}

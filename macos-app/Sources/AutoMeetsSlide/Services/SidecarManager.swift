import Foundation
import os

/// Commands that can be sent to the Python sidecar
enum SidecarCommand {
    case checkAuth
    case process(filePath: String, outputDir: String, systemPrompt: String?, jobId: String)
    case findNotebook(jobId: String)
    case checkStatus(notebookId: String, taskId: String)
    case download(notebookId: String, outputDir: String, fileNameStem: String)

    var arguments: [String] {
        switch self {
        case .checkAuth:
            return ["check-auth"]
        case .process(let filePath, let outputDir, let systemPrompt, let jobId):
            var args = ["process", filePath, outputDir, "--job-id", jobId]
            if let prompt = systemPrompt {
                args += ["--system-prompt", prompt]
            }
            return args
        case .findNotebook(let jobId):
            return ["find-notebook", jobId]
        case .checkStatus(let notebookId, let taskId):
            return ["check-status", notebookId, taskId]
        case .download(let notebookId, let outputDir, let fileNameStem):
            return ["download", notebookId, outputDir, "--name", fileNameStem]
        }
    }
}

/// Response from the Python sidecar (JSON format)
struct SidecarResponse: Decodable {
    let status: String?
    let message: String?
    let error: String?
    let authenticated: Bool?
    let outputPath: String?
    let notebookId: String?
    let taskId: String?
    let generationStatus: String?
    let isComplete: Bool?
    let isFailed: Bool?

    enum CodingKeys: String, CodingKey {
        case status, message, error, authenticated
        case outputPath = "output_path"
        case notebookId = "notebook_id"
        case taskId = "task_id"
        case generationStatus = "generation_status"
        case isComplete = "is_complete"
        case isFailed = "is_failed"
    }
}

/// Manages communication with the Python sidecar process
@MainActor
@Observable
class SidecarManager {
    var currentStatus: String = "Ready"
    var isRunning: Bool = false

    private var currentProcess: Process?

    /// Run a sidecar command and return the final response
    func run(_ command: SidecarCommand, onProgress: ((SidecarResponse) -> Void)? = nil) async throws -> SidecarResponse? {
        isRunning = true
        defer { isRunning = false }

        // Thread-safe state for concurrent access from readabilityHandler
        let state = OSAllocatedUnfairLock(initialState: (outputBuffer: "", lastResponse: SidecarResponse?.none))

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()

            process.executableURL = sidecarURL
            process.arguments = command.arguments
            process.standardOutput = stdout
            process.standardError = stderr
            process.environment = ProcessInfo.processInfo.environment

            // Handle stdout line by line for progress updates
            stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }

                let responses = state.withLock { state -> [SidecarResponse] in
                    state.outputBuffer += String(data: data, encoding: .utf8) ?? ""

                    var parsed: [SidecarResponse] = []

                    // Process complete lines
                    while let newlineRange = state.outputBuffer.range(of: "\n") {
                        let line = String(state.outputBuffer[..<newlineRange.lowerBound])
                        state.outputBuffer = String(state.outputBuffer[newlineRange.upperBound...])

                        guard !line.isEmpty else { continue }

                        if let jsonData = line.data(using: .utf8),
                           let response = try? JSONDecoder().decode(SidecarResponse.self, from: jsonData) {
                            state.lastResponse = response
                            parsed.append(response)
                        }
                    }

                    return parsed
                }

                for response in responses {
                    Task { @MainActor in
                        if let message = response.message {
                            self?.currentStatus = message
                        }
                        if let error = response.error {
                            self?.currentStatus = "Error: \(error)"
                        }
                        onProgress?(response)
                    }
                }
            }

            process.terminationHandler = { _ in
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                let finalResponse = state.withLock { $0.lastResponse }
                continuation.resume(returning: finalResponse)
            }

            do {
                try process.run()
                currentProcess = process
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Get the URL to the sidecar binary
    private var sidecarURL: URL {
        // In bundled app - binary is in Contents/MacOS/
        if let executableURL = Bundle.main.executableURL {
            let bundledURL = executableURL.deletingLastPathComponent().appendingPathComponent("notebooklm-cli")
            if FileManager.default.fileExists(atPath: bundledURL.path) {
                return bundledURL
            }
        }

        // Development fallback - use the Python sidecar directly from dist
        return URL(fileURLWithPath: "/Users/hiko/Documents/repos/Work/AutoMeetsSlide/python-sidecar/dist/notebooklm-cli")
    }

    /// Cancel the current process
    func cancel() {
        currentProcess?.terminate()
        currentProcess = nil
    }
}

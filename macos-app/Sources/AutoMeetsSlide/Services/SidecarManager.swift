import Foundation
import os

/// Commands that can be sent to the Python sidecar
enum SidecarCommand {
    case checkAuth
    case process(filePath: String, outputDir: String, systemPrompt: String?, jobId: String, additionalFiles: [String] = [], sourceURLs: [String] = [])
    case findNotebook(jobId: String)
    case checkStatus(notebookId: String, taskId: String)
    case download(notebookId: String, outputDir: String, fileNameStem: String)

    var arguments: [String] {
        switch self {
        case .checkAuth:
            return ["check-auth"]
        case .process(let filePath, let outputDir, let systemPrompt, let jobId, let additionalFiles, let sourceURLs):
            var args = ["process", filePath, outputDir, "--job-id", jobId]
            if let prompt = systemPrompt {
                args += ["--system-prompt", prompt]
            }
            for additionalFile in additionalFiles {
                args += ["--source-file", additionalFile]
            }
            for url in sourceURLs {
                args += ["--source-url", url]
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

/// Manages communication with the Python sidecar process.
/// Stateless — each `run()` call spawns an independent process, safe for concurrent use.
class SidecarManager {

    /// Run a sidecar command and return the final response
    @MainActor
    func run(_ command: SidecarCommand, onProgress: ((SidecarResponse) -> Void)? = nil) async throws -> SidecarResponse? {
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

            // Drain stderr asynchronously to prevent pipe buffer blockage
            stderr.fileHandleForReading.readabilityHandler = { handle in
                _ = handle.availableData
            }

            // Parse JSON lines from stdout
            stdout.fileHandleForReading.readabilityHandler = { handle in
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
                        onProgress?(response)
                    }
                }
            }

            process.terminationHandler = { _ in
                // Stop readability handlers
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil

                // Flush remaining stdout data
                let remainingData = stdout.fileHandleForReading.readDataToEndOfFile()
                if !remainingData.isEmpty {
                    state.withLock { state in
                        state.outputBuffer += String(data: remainingData, encoding: .utf8) ?? ""
                        while let newlineRange = state.outputBuffer.range(of: "\n") {
                            let line = String(state.outputBuffer[..<newlineRange.lowerBound])
                            state.outputBuffer = String(state.outputBuffer[newlineRange.upperBound...])
                            guard !line.isEmpty else { continue }
                            if let jsonData = line.data(using: .utf8),
                               let response = try? JSONDecoder().decode(SidecarResponse.self, from: jsonData) {
                                state.lastResponse = response
                            }
                        }
                    }
                }

                // Capture stderr for error diagnostics
                let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
                let stderrText = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)

                let finalResponse = state.withLock { $0.lastResponse }

                // If process failed with no JSON error, surface stderr
                if finalResponse?.error == nil,
                   finalResponse?.outputPath == nil,
                   let stderrText, !stderrText.isEmpty {
                    Log.sidecar.error("Sidecar stderr: \(stderrText)")
                }

                continuation.resume(returning: finalResponse)
            }

            do {
                try process.run()
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
}

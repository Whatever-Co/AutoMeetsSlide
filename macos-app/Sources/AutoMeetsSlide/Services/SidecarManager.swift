import Foundation

/// Commands that can be sent to the Python sidecar
enum SidecarCommand {
    case checkAuth
    case process(filePath: String, outputDir: String, systemPrompt: String?)

    var arguments: [String] {
        switch self {
        case .checkAuth:
            return ["check-auth"]
        case .process(let filePath, let outputDir, let systemPrompt):
            var args = ["process", filePath, outputDir]
            if let prompt = systemPrompt {
                args += ["--system-prompt", prompt]
            }
            return args
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

    enum CodingKeys: String, CodingKey {
        case status, message, error, authenticated
        case outputPath = "output_path"
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

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()

            process.executableURL = sidecarURL
            process.arguments = command.arguments
            process.standardOutput = stdout
            process.standardError = stderr
            process.environment = ProcessInfo.processInfo.environment

            var lastResponse: SidecarResponse?
            var outputBuffer = ""

            // Handle stdout line by line for progress updates
            stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }

                outputBuffer += String(data: data, encoding: .utf8) ?? ""

                // Process complete lines
                while let newlineRange = outputBuffer.range(of: "\n") {
                    let line = String(outputBuffer[..<newlineRange.lowerBound])
                    outputBuffer = String(outputBuffer[newlineRange.upperBound...])

                    guard !line.isEmpty else { continue }

                    if let jsonData = line.data(using: .utf8),
                       let response = try? JSONDecoder().decode(SidecarResponse.self, from: jsonData) {
                        lastResponse = response

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
            }

            process.terminationHandler = { _ in
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                continuation.resume(returning: lastResponse)
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

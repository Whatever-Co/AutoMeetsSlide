import Foundation

/// Represents a file in the processing queue
struct FileItem: Identifiable, Equatable, Codable {
    let id: UUID
    let path: String
    let name: String
    let format: String
    let size: Int64
    var status: ProcessingStatus
    var outputPath: String?
    var notebookId: String?
    var error: String?
    let addedAt: Date

    // Per-job settings
    var additionalPaths: [String]
    var sourceURLs: [String]
    var customPrompt: String?

    init(url: URL) {
        self.id = UUID()
        self.path = url.path
        self.name = url.lastPathComponent
        self.format = url.pathExtension.uppercased()
        self.size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        self.status = .pending
        self.outputPath = nil
        self.notebookId = nil
        self.error = nil
        self.addedAt = Date()
        self.additionalPaths = []
        self.sourceURLs = []
        self.customPrompt = nil
    }
}

/// Processing status for a file
enum ProcessingStatus: String, Equatable, Codable {
    case pending
    case processing
    case restoring
    case completed
    case error

    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .processing: return "Processing..."
        case .restoring: return "Restoring..."
        case .completed: return "Completed"
        case .error: return "Error"
        }
    }
}

/// Supported file extensions
enum SupportedFileType {
    static let audio: Set<String> = ["mp3", "wav", "m4a"]
    static let document: Set<String> = ["pdf", "txt", "md", "docx"]
    static let all: Set<String> = audio.union(document)

    static func isSupported(_ url: URL) -> Bool {
        all.contains(url.pathExtension.lowercased())
    }
}

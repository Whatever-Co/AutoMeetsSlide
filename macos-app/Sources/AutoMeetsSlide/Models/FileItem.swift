import Foundation

/// Represents a file in the processing queue
struct FileItem: Identifiable, Equatable {
    let id: UUID
    let path: String
    let name: String
    let format: String
    let size: Int64
    var status: ProcessingStatus
    var outputPath: String?
    var error: String?
    let addedAt: Date

    init(url: URL) {
        self.id = UUID()
        self.path = url.path
        self.name = url.lastPathComponent
        self.format = url.pathExtension.uppercased()
        self.size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        self.status = .pending
        self.outputPath = nil
        self.error = nil
        self.addedAt = Date()
    }
}

/// Processing status for a file
enum ProcessingStatus: String, Equatable {
    case pending
    case processing
    case completed
    case error

    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .processing: return "Processing..."
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

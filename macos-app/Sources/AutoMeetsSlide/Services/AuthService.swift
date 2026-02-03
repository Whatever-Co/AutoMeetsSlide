import Foundation

/// Manages authentication state and storage paths
enum AuthService {

    /// Default path where notebooklm-py expects storage_state.json
    static var storageStatePath: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".notebooklm/storage_state.json")
    }

    /// Check if storage state file exists and is recent enough
    static func hasValidStorageState() -> Bool {
        let url = storageStatePath
        guard FileManager.default.fileExists(atPath: url.path) else {
            return false
        }

        // Check if file was modified within last 24 hours
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modDate = attrs[.modificationDate] as? Date
        else {
            return false
        }

        let age = Date().timeIntervalSince(modDate)
        return age < 86400  // 24 hours
    }

    /// Clear stored authentication
    static func clearStorageState() {
        try? FileManager.default.removeItem(at: storageStatePath)
    }
}

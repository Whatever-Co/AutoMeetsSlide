import Foundation
import os.log

/// App-wide logger using os.log
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "AutoMeetsSlide"

    static let auth = Logger(subsystem: subsystem, category: "auth")
    static let sidecar = Logger(subsystem: subsystem, category: "sidecar")
    static let ui = Logger(subsystem: subsystem, category: "ui")
    static let general = Logger(subsystem: subsystem, category: "general")
    static let watcher = Logger(subsystem: subsystem, category: "watcher")
}

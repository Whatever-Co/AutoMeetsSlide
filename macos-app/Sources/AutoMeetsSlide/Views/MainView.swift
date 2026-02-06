import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// AppKit-based drop zone that reads file URLs directly from the dragging pasteboard
struct FileDropZone: NSViewRepresentable {
    @Binding var isDragOver: Bool
    let onDrop: ([URL]) -> Void

    func makeNSView(context: Context) -> DropTargetView {
        let view = DropTargetView()
        view.onDragEntered = { urls in isDragOver = urls.contains { SupportedFileType.isSupported($0) } }
        view.onDragExited = { isDragOver = false }
        view.onDrop = { urls in
            isDragOver = false
            let supported = urls.filter { SupportedFileType.isSupported($0) }
            if !supported.isEmpty { onDrop(supported) }
        }
        view.onDragUpdated = { urls in urls.contains { SupportedFileType.isSupported($0) } }
        return view
    }

    func updateNSView(_ nsView: DropTargetView, context: Context) {}
}

class DropTargetView: NSView {
    var onDragEntered: (([URL]) -> Void)?
    var onDragExited: (() -> Void)?
    var onDrop: (([URL]) -> Void)?
    var onDragUpdated: (([URL]) -> Bool)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func urls(from draggingInfo: NSDraggingInfo) -> [URL] {
        draggingInfo.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] ?? []
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let files = urls(from: sender)
        onDragEntered?(files)
        return files.contains(where: { SupportedFileType.isSupported($0) }) ? .copy : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let files = urls(from: sender)
        return onDragUpdated?(files) == true ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDragExited?()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let files = urls(from: sender)
        onDrop?(files)
        return true
    }
}

/// Main app view after authentication
struct MainView: View {
    private var appState: AppState { AppState.shared }
    @State private var isDragOver = false

    var body: some View {
        VStack(spacing: 0) {
            // Content
            if appState.files.isEmpty {
                emptyStateView
            } else {
                fileListView
            }

            // Status bar
            if appState.sidecarManager.isRunning {
                statusBar
            }
        }
        .overlay {
            FileDropZone(isDragOver: $isDragOver) { urls in
                appState.addFiles(urls)
            }
        }
        .overlay {
            if isDragOver {
                dropOverlay
            }
        }
        .task {
            await processLoop()
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.up.doc")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Drop files here or click to select")
                .font(.headline)

            Text("MP3, WAV, M4A, PDF, TXT, MD, DOCX")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Button("Select Files", action: appState.selectFiles)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture(perform: appState.selectFiles)
    }

    // MARK: - File List

    private var fileListView: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(appState.files) { file in
                    FileRowView(file: file) {
                        appState.removeFile(file.id)
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack {
            ProgressView()
                .scaleEffect(0.7)
            Text(appState.sidecarManager.currentStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Drop Overlay

    private var dropOverlay: some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10]))
            .background(Color.accentColor.opacity(0.1))
            .padding()
    }

    // MARK: - Actions

    private func processLoop() async {
        while true {
            await appState.processNextFile()
            try? await Task.sleep(for: .seconds(1))
        }
    }
}

/// Row view for a single file
struct FileRowView: View {
    let file: FileItem
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // File icon
            Image(systemName: fileIcon)
                .font(.title2)
                .foregroundStyle(iconColor)
                .frame(width: 32)

            // File info
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(file.format)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary)
                        .clipShape(Capsule())

                    Text(file.status.displayName)
                        .font(.caption)
                        .foregroundStyle(statusColor)

                    if let error = file.error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            // Actions
            if file.status == .processing || file.status == .restoring {
                ProgressView()
                    .scaleEffect(0.7)
            } else if file.status == .completed, let outputPath = file.outputPath {
                Button {
                    NSWorkspace.shared.selectFile(outputPath, inFileViewerRootedAtPath: "")
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
            }

            if file.status != .processing && file.status != .restoring {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var fileIcon: String {
        switch file.status {
        case .completed: return "checkmark.circle.fill"
        case .error: return "exclamationmark.circle.fill"
        case .processing, .restoring: return "arrow.triangle.2.circlepath"
        default:
            if SupportedFileType.audio.contains(file.format.lowercased()) {
                return "waveform"
            } else {
                return "doc"
            }
        }
    }

    private var iconColor: Color {
        switch file.status {
        case .completed: return .green
        case .error: return .red
        case .processing, .restoring: return .blue
        default: return .secondary
        }
    }

    private var statusColor: Color {
        switch file.status {
        case .completed: return .green
        case .error: return .red
        case .processing, .restoring: return .blue
        default: return .secondary
        }
    }
}

#Preview {
    MainView()
}

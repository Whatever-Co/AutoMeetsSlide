import SwiftUI
import UniformTypeIdentifiers

/// Drop delegate that only accepts supported file types
struct FileDropDelegate: DropDelegate {
    @Binding var isDragOver: Bool
    let onDrop: ([URL]) -> Void

    private func hasSupportedFiles(info: DropInfo) -> Bool {
        guard info.hasItemsConforming(to: [.fileURL]) else { return false }

        let providers = info.itemProviders(for: [.fileURL])
        for provider in providers {
            // Check suggestedName for file extension
            if let name = provider.suggestedName {
                let ext = (name as NSString).pathExtension.lowercased()
                if SupportedFileType.all.contains(ext) {
                    return true
                }
            }
        }
        return false
    }

    func validateDrop(info: DropInfo) -> Bool {
        hasSupportedFiles(info: info)
    }

    func dropEntered(info: DropInfo) {
        isDragOver = hasSupportedFiles(info: info)
    }

    func dropExited(info: DropInfo) {
        isDragOver = false
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        hasSupportedFiles(info: info) ? DropProposal(operation: .copy) : DropProposal(operation: .cancel)
    }

    func performDrop(info: DropInfo) -> Bool {
        isDragOver = false

        let providers = info.itemProviders(for: [.fileURL])
        var urls: [URL] = []

        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                defer { group.leave() }
                guard let data = data as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil),
                      SupportedFileType.isSupported(url) else { return }
                urls.append(url)
            }
        }

        group.notify(queue: .main) {
            if !urls.isEmpty {
                onDrop(urls)
            }
        }

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
        .onDrop(of: [.fileURL], delegate: FileDropDelegate(isDragOver: $isDragOver) { urls in
            appState.addFiles(urls)
        })
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
            if file.status == .processing {
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

            if file.status != .processing {
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
        case .processing: return "arrow.triangle.2.circlepath"
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
        case .processing: return .blue
        default: return .secondary
        }
    }

    private var statusColor: Color {
        switch file.status {
        case .completed: return .green
        case .error: return .red
        case .processing: return .blue
        default: return .secondary
        }
    }
}

#Preview {
    MainView()
}

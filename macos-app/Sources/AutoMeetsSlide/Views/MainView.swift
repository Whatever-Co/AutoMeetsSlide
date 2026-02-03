import SwiftUI
import UniformTypeIdentifiers

/// Main app view after authentication
struct MainView: View {
    @State private var appState = AppState.shared
    @State private var isDragOver = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

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
        .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
            handleDrop(providers)
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

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Text("AutoMeetsSlide")
                .font(.headline)

            Spacer()

            Button(action: selectFiles) {
                Label("Add Files", systemImage: "plus")
            }

            Menu {
                Button("Logout", action: appState.logout)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 30)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.up.doc")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Drop files here or click to select")
                .font(.headline)

            Text("MP3, WAV, M4A, PDF, TXT, DOCX")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Button("Select Files", action: selectFiles)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture(perform: selectFiles)
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

    private func selectFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            .mp3, .wav, .mpeg4Audio,
            .pdf, .plainText,
            UTType(filenameExtension: "docx")!
        ]

        if panel.runModal() == .OK {
            appState.addFiles(panel.urls)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                guard let data = data as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil)
                else { return }

                Task { @MainActor in
                    appState.addFiles([url])
                }
            }
        }
        return true
    }

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

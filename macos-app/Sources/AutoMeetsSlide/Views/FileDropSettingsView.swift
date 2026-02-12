import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings sheet shown when files are dropped, before queuing for processing
struct FileDropSettingsView: View {
    @State var droppedFiles: [URL]
    @State private var sourceURLs: [String] = []
    @State private var urlInput: String = ""
    @State private var prompt: String = AppState.defaultSystemPrompt
    @State private var isDragOver = false
    let onGenerate: (_ files: [URL], _ sourceURLs: [String], _ prompt: String) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            Text("New Slide Deck")
                .font(.headline)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Sources section
                    sourcesSection

                    Divider()

                    // Google Doc / URL section
                    urlSection

                    Divider()

                    // Prompt section
                    promptSection
                }
                .padding(20)
            }

            Divider()

            // Footer buttons
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Generate", action: generate)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(droppedFiles.isEmpty && sourceURLs.isEmpty)
            }
            .padding(16)
        }
        .frame(width: 480, height: 560)
        .onAppear {
            // Load saved prompt
            prompt = AppState.shared.systemPrompt
        }
    }

    // MARK: - Sources

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sources")
                .font(.subheadline)
                .fontWeight(.semibold)

            // File list
            VStack(spacing: 4) {
                ForEach(droppedFiles, id: \.self) { url in
                    HStack(spacing: 8) {
                        Image(systemName: fileIcon(for: url))
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        Text(url.lastPathComponent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(url.pathExtension.uppercased())
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.quaternary)
                            .clipShape(Capsule())
                        Button {
                            droppedFiles.removeAll { $0 == url }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

            // Drop zone for additional files
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isDragOver ? Color.accentColor : Color(nsColor: .separatorColor),
                        style: StrokeStyle(lineWidth: 1.5, dash: [6])
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isDragOver ? Color.accentColor.opacity(0.05) : Color.clear)
                    )

                VStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                    Text("Drop files to add more")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(height: 52)
            .overlay {
                FileDropZone(isDragOver: $isDragOver) { urls in
                    let supported = urls.filter { SupportedFileType.isSupported($0) }
                    let existing = Set(droppedFiles.map(\.path))
                    let newFiles = supported.filter { !existing.contains($0.path) }
                    droppedFiles.append(contentsOf: newFiles)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                selectAdditionalFiles()
            }
        }
    }

    // MARK: - URL Section

    private var urlSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Web / Google Docs URL")
                .font(.subheadline)
                .fontWeight(.semibold)

            HStack(spacing: 8) {
                TextField("https://docs.google.com/document/d/...", text: $urlInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addURL() }

                Button(action: addURL) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .disabled(urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            // URL list
            ForEach(sourceURLs, id: \.self) { url in
                HStack(spacing: 8) {
                    Image(systemName: "link")
                        .foregroundStyle(.blue)
                        .frame(width: 16)
                    Text(url)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button {
                        sourceURLs.removeAll { $0 == url }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    // MARK: - Prompt Section

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Prompt")
                .font(.subheadline)
                .fontWeight(.semibold)

            TextEditor(text: $prompt)
                .font(.body)
                .frame(height: 80)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )

            HStack {
                Spacer()
                Button("Reset to Default") {
                    prompt = AppState.defaultSystemPrompt
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        }
    }

    // MARK: - Actions

    private func generate() {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        onGenerate(droppedFiles, sourceURLs, trimmedPrompt.isEmpty ? AppState.defaultSystemPrompt : trimmedPrompt)
    }

    private func addURL() {
        let trimmed = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard URL(string: trimmed) != nil else { return }
        if !sourceURLs.contains(trimmed) {
            sourceURLs.append(trimmed)
        }
        urlInput = ""
    }

    private func selectAdditionalFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            .mp3, .wav, .mpeg4Audio,
            .pdf, .plainText,
            UTType(filenameExtension: "docx")!
        ]

        if panel.runModal() == .OK {
            let existing = Set(droppedFiles.map(\.path))
            let newFiles = panel.urls.filter {
                SupportedFileType.isSupported($0) && !existing.contains($0.path)
            }
            droppedFiles.append(contentsOf: newFiles)
        }
    }

    private func fileIcon(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if SupportedFileType.audio.contains(ext) {
            return "waveform"
        } else {
            return "doc"
        }
    }
}

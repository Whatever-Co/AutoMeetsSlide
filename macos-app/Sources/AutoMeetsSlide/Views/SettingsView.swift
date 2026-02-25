import SwiftUI

struct SettingsView: View {
    private var appState: AppState { AppState.shared }
    private var folderWatcher: FolderWatcherService { FolderWatcherService.shared }

    @State private var systemPrompt: String = ""
    @State private var downloadFolder: String = ""
    @State private var maxConcurrency: Int = 3
    @State private var autoDeleteNotebook: Bool = false

    var body: some View {
        Form {
            // Slide Generation
            Section("Slide Generation") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("System Prompt")
                        .font(.headline)

                    TextEditor(text: $systemPrompt)
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
                            systemPrompt = AppState.defaultSystemPrompt
                        }
                        .buttonStyle(.link)
                    }
                }
            }

            // Concurrent Processing
            Section("Concurrent Processing") {
                HStack {
                    Text("Max Concurrent Jobs")
                    Spacer()
                    Picker("", selection: $maxConcurrency) {
                        ForEach(1...5, id: \.self) { n in
                            Text("\(n)").tag(n)
                        }
                    }
                    .frame(width: 80)
                }
                Text("Number of files to process simultaneously.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            // Output
            Section("Output") {
                HStack {
                    Text("Download Folder")
                    Spacer()
                    Text(URL(fileURLWithPath: downloadFolder).lastPathComponent)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Button("Choose...") {
                        selectDownloadFolder()
                    }
                }
            }

            // Notebook
            Section("Notebook") {
                Toggle("Auto-delete notebook after download", isOn: $autoDeleteNotebook)
                Text("Automatically delete the NotebookLM notebook after the slide PDF is downloaded.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            // About
            Section {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"))")
                        .foregroundStyle(.secondary)
                }
            }

            // Auto Import
            Section("Auto Import") {
                if let watchPath = folderWatcher.watchedFolderPath {
                    HStack {
                        Image(systemName: "folder.badge.gearshape")
                            .foregroundStyle(.green)
                        Text(URL(fileURLWithPath: watchPath).lastPathComponent)
                            .lineLimit(1)
                        Spacer()
                        Button("Stop Watching") {
                            folderWatcher.clearWatchedFolder()
                        }
                    }
                } else {
                    HStack {
                        Text("No folder selected")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Watch Folder...") {
                            Task {
                                await folderWatcher.selectFolder()
                            }
                        }
                    }
                }

                Text("New M4A files in the watched folder will be automatically added to the queue.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 450)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            systemPrompt = appState.systemPrompt
            downloadFolder = appState.downloadFolder
            maxConcurrency = appState.maxConcurrency
            autoDeleteNotebook = appState.autoDeleteNotebook
        }
        .onChange(of: systemPrompt) { _, newValue in
            appState.systemPrompt = newValue
        }
        .onChange(of: downloadFolder) { _, newValue in
            appState.downloadFolder = newValue
        }
        .onChange(of: maxConcurrency) { _, newValue in
            appState.maxConcurrency = newValue
        }
        .onChange(of: autoDeleteNotebook) { _, newValue in
            appState.autoDeleteNotebook = newValue
        }
    }

    private func selectDownloadFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Select"
        panel.message = "Select download folder for generated PDFs"

        if panel.runModal() == .OK, let url = panel.url {
            downloadFolder = url.path
        }
    }
}

#Preview {
    SettingsView()
}

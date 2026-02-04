# AutoMeetsSlide

macOS app that automatically converts documents to slide decks using Google NotebookLM.

## Project Structure

```
AutoMeetsSlide/
├── macos-app/                    # Native macOS SwiftUI app
│   ├── project.yml               # XcodeGen project definition
│   ├── Sources/AutoMeetsSlide/
│   │   ├── AutoMeetsSlideApp.swift    # App entry point
│   │   ├── Models/
│   │   │   └── FileItem.swift         # File queue item model
│   │   ├── ViewModels/
│   │   │   └── AppState.swift         # Main app state (Observable)
│   │   ├── Views/
│   │   │   ├── ContentView.swift      # Root view (auth routing)
│   │   │   ├── MainView.swift         # Main UI (file drop, queue)
│   │   │   └── LoginView.swift        # Login UI
│   │   ├── Components/
│   │   │   └── GoogleLoginWebView.swift  # WKWebView for Google auth
│   │   ├── Services/
│   │   │   ├── SidecarManager.swift   # Python sidecar communication
│   │   │   ├── AuthService.swift      # Authentication (Safari cookies)
│   │   │   ├── StorageStateConverter.swift
│   │   │   └── NotificationManager.swift  # macOS notifications
│   │   ├── Utilities/
│   │   │   └── Logger.swift           # os.log wrapper
│   │   └── Resources/
│   │       └── Binaries/
│   │           └── notebooklm-cli     # Python sidecar binary
│   └── scripts/
│       ├── release-build.sh          # Release build script
│       └── notarize.sh               # App notarization
│
├── python-sidecar/               # Python CLI for NotebookLM API
│   ├── notebooklm_sidecar.py     # Main CLI (login, check-auth, process)
│   ├── notebooklm-cli.spec       # PyInstaller spec
│   └── requirements.txt          # Dependencies (notebooklm-py)
│
└── tauri-app/                    # OBSOLETE - will be deleted
```

## Architecture

### macOS App (SwiftUI)
- **AppState**: Central state management using `@Observable`
- **SidecarManager**: Spawns and communicates with Python binary via JSON stdout
- **AuthService**: Extracts Safari cookies for silent authentication
- **NotificationManager**: macOS native notifications for completion/failure

### Python Sidecar
- Compiled binary using PyInstaller
- Commands: `login`, `check-auth`, `process`
- Communicates via JSON on stdout
- Uses `notebooklm-py` library for NotebookLM API

### Data Flow
1. User drops file → FileItem added to queue (pending)
2. AppState.processNextFile() → SidecarManager.run(.process)
3. Python sidecar → NotebookLM API → PDF download
4. SidecarManager parses JSON response → AppState updates status
5. NotificationManager sends macOS notification

## Development

### Prerequisites
- Xcode 16+
- Python 3.10+
- XcodeGen (`brew install xcodegen`)

### Build macOS App
```bash
cd macos-app
xcodegen generate       # Regenerate project after adding files
xcodebuild -scheme AutoMeetsSlide -configuration Debug build
```

### Build Python Sidecar
```bash
cd python-sidecar
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
pip install pyinstaller

pyinstaller --onefile --name notebooklm-cli notebooklm_sidecar.py
cp dist/notebooklm-cli ../macos-app/Sources/AutoMeetsSlide/Resources/Binaries/
```

### Release Build
```bash
cd macos-app
./scripts/release-build.sh
./scripts/notarize.sh   # Requires Apple Developer credentials
```

## Key Files

| File | Purpose |
|------|---------|
| `AppState.swift` | Main state, file queue, processing logic |
| `SidecarManager.swift` | Python binary communication |
| `notebooklm_sidecar.py` | NotebookLM API wrapper |
| `project.yml` | XcodeGen project definition |

## Notes

- Bundle ID: `sh.saqoo.AutoMeetsSlide`
- Uses `jj` for version control (not git directly)
- Supported file types: PDF, audio (mp3, wav, m4a), video (mp4, mov, webm)

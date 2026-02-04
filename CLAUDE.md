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
│       ├── build.sh                  # Build script (Debug/Release)
│       ├── notarize.sh               # Code signing & notarization
│       ├── package_dmg.sh            # DMG packaging (build + notarize + DMG)
│       └── release.sh                # Full release workflow
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

### Build via Claude Code (Recommended)

XcodeBuildMCP is configured for this project. Use natural language:

| Instruction | Action |
|-------------|--------|
| "build it" / "ビルドして" | `build_macos` |
| "run the app" / "起動して" | `build_macos` → `launch_mac_app` |
| "stop the app" / "止めて" | `stop_mac_app` |
| "rebuild and run" | `stop_mac_app` → `build_macos` → `launch_mac_app` |
| "test it" | `test_macos` |
| "clean build" | `clean` → `build_macos` |

Session defaults are configured in `.xcodebuildmcp/config.yaml`.

**Note**: `stop_mac_app` requires explicit `appName: "AutoMeetsSlide"` parameter (not auto-filled from defaults).

### Build macOS App (Manual)
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

pyinstaller notebooklm-cli.spec
cp dist/notebooklm-cli ../macos-app/Sources/AutoMeetsSlide/Resources/Binaries/
```

### Release Build
```bash
cd macos-app
./scripts/package_dmg.sh   # Build, notarize, and create DMG
```

### Release a New Version
```bash
cd macos-app
./scripts/release.sh <version>   # e.g., ./scripts/release.sh 1.0.0
```

This will bump version, build DMG, commit, tag, and create GitHub Release.

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

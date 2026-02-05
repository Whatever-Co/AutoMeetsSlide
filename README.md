# AutoMeetsSlide

<p align="center">
  <img src="macos-app/images/appicon.png" width="128" height="128" alt="AutoMeetsSlide icon">
  <br>
  A macOS app that automatically converts documents to slide decks using Google NotebookLM.
</p>

## Features

- **Drag & Drop** - Drop files directly onto the window to process
- **Watch Folder** - Automatically process new files in a designated folder
- **Multiple Formats** - Supports PDF, audio (mp3, wav, m4a), and video (mp4, mov, webm)
- **Native Notifications** - macOS notifications on completion or failure
- **Silent Authentication** - Uses Safari cookies for seamless Google login

## Installation

1. Download the latest `.dmg` from [Releases](https://github.com/Whatever-Co/AutoMeetsSlide/releases)
2. Open the DMG and drag `AutoMeetsSlide.app` to Applications
3. Launch the app and sign in with your Google account

## Usage

### Processing Files

1. Drag & drop files onto the app window, or
2. Set up a watch folder for automatic processing

### Requirements

- macOS 14.0+
- Google account with NotebookLM access
- Safari logged into Google (for silent auth)

---

## Development

### Requirements

- macOS 14.0+
- Xcode 16.0+
- Python 3.10+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

### Build from Source

```bash
git clone https://github.com/Whatever-Co/AutoMeetsSlide.git
cd AutoMeetsSlide

# Build Python sidecar first
cd python-sidecar
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
pip install pyinstaller
pyinstaller notebooklm-cli.spec

# Build macOS app
cd ../macos-app
./scripts/build.sh Release

# The app is located at:
# build/DerivedData/Build/Products/Release/AutoMeetsSlide.app
```

### Build Commands

```bash
./scripts/build.sh          # Debug build
./scripts/build.sh Release  # Release build
./scripts/package_dmg.sh    # Package DMG (includes notarization)
./scripts/release.sh 1.0.0  # Release new version
```

### Tech Stack

- Swift 5.9 + SwiftUI
- Python 3.10 + [notebooklm-py](https://github.com/nicobrenner/notebooklm-py)
- PyInstaller (sidecar binary)

### Project Structure

```
AutoMeetsSlide/
├── macos-app/              # Native macOS SwiftUI app
│   ├── project.yml         # XcodeGen project definition
│   ├── Sources/
│   ├── images/             # Source images (app icon base)
│   └── scripts/            # Build, release & icon scripts
│
└── python-sidecar/         # Python CLI for NotebookLM API
    ├── notebooklm_sidecar.py
    └── notebooklm-cli.spec
```

## License

Proprietary - Whatever Co.

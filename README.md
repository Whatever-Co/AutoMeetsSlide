# NotebookLM Slide Generator (Tauri + Python)

## Prerequisites
- Node.js (v18+)
- Rust (cargo)
- Python 3.10+

## 1. Build the Python Sidecar (Mac)
First, you need to compile the Python logic into a binary for macOS.

```bash
cd python-sidecar
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
pip install pyinstaller

# Build the binary
pyinstaller --onefile --name notebooklm-cli ../../notebooklm_sidecar.py
```

Move the binary to Tauri's binary folder:
```bash
mkdir -p ../tauri-app/src-tauri/binaries
# Note: Tauri requires target triple in filename for sidecars
# Run `rustc -vV` to see your host target (e.g., aarch64-apple-darwin)
cp dist/notebooklm-cli ../tauri-app/src-tauri/binaries/notebooklm-cli-aarch64-apple-darwin
```

## 2. Setup Tauri App
```bash
cd ../tauri-app
npm install
```

## 3. Run Dev
```bash
npm run tauri dev
```

## 4. Build App (.dmg / .app)
```bash
npm run tauri build
```

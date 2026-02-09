Remove all existing AutoMeetsSlide.app instances, download the latest release from GitHub, and install it.

## Steps

### 1. Version check

Get the latest release version from GitHub:

```bash
gh release list --limit 1
```

Get the currently installed version:

```bash
defaults read /Applications/AutoMeetsSlide.app/Contents/Info.plist CFBundleShortVersionString 2>/dev/null
```

If both versions match, skip all remaining steps and report:
"AutoMeetsSlide vX.X.X is already the latest version. No update needed."

### 2. Quit running AutoMeetsSlide if any

```bash
osascript -e 'quit app "AutoMeetsSlide"'
```

### 3. Find and remove all AutoMeetsSlide.app instances

```bash
mdfind "kMDItemFSName == 'AutoMeetsSlide.app'"
```

Remove all found instances including:
- `/Applications/AutoMeetsSlide.app`
- Any build artifacts in the project's `build/` directory

### 4. Download latest release

Download the DMG from the latest release:

```bash
gh release download <latest_tag> --pattern '*.dmg' --dir <scratchpad>
```

### 5. Install

Mount the DMG, copy to `/Applications/`, and unmount:

```bash
hdiutil attach <dmg_path> -nobrowse
cp -R "/Volumes/AutoMeetsSlide/AutoMeetsSlide.app" /Applications/
hdiutil detach "/Volumes/AutoMeetsSlide"
```

### 6. Open the app

```bash
open /Applications/AutoMeetsSlide.app
```

### 7. Report

Display the installed version.

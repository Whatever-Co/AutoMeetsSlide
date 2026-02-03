#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_ROOT="$(cd "${ROOT_DIR}/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build"
DERIVED_DATA_DIR="${BUILD_DIR}/DerivedData"

CONFIGURATION="${1:-Debug}"

mkdir -p "${BUILD_DIR}"

# Ensure sidecar binary exists in Resources/Binaries
SIDECAR_SRC="${PROJECT_ROOT}/python-sidecar/dist/notebooklm-cli"
SIDECAR_DST="${ROOT_DIR}/Sources/AutoMeetsSlide/Resources/Binaries/notebooklm-cli"

if [[ ! -f "$SIDECAR_SRC" ]]; then
  echo "Error: Sidecar binary not found at $SIDECAR_SRC"
  echo "Please build the Python sidecar first:"
  echo "  cd ${PROJECT_ROOT}/python-sidecar && pyinstaller notebooklm-cli.spec"
  exit 1
fi

echo "=== Copying sidecar binary ==="
mkdir -p "$(dirname "$SIDECAR_DST")"
cp "$SIDECAR_SRC" "$SIDECAR_DST"

# Regenerate Xcode project from project.yml
echo "=== Generating Xcode project ==="
xcodegen generate --spec "${ROOT_DIR}/project.yml"

echo "=== Building ${CONFIGURATION} ==="
xcodebuild \
  -scheme AutoMeetsSlide \
  -configuration "${CONFIGURATION}" \
  -destination 'platform=macOS' \
  -derivedDataPath "${DERIVED_DATA_DIR}" \
  build

APP_PATH="${DERIVED_DATA_DIR}/Build/Products/${CONFIGURATION}/AutoMeetsSlide.app"

# Copy sidecar binary into app bundle
echo "=== Copying sidecar into app bundle ==="
cp "$SIDECAR_SRC" "${APP_PATH}/Contents/MacOS/notebooklm-cli"

echo "=== Built app ==="
echo "${APP_PATH}"
ls -la "${APP_PATH}/Contents/MacOS/"

#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
VERSION=0.8.0
ARCH=$(uname -m)
case "$ARCH" in arm64|x86_64) ;; *) echo "Неподдерживаемая архитектура: $ARCH"; exit 1;; esac
PYTHON_BIN=${PYTHON_BIN:-python3}
BUILD_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/sibka-package.XXXXXX")
trap 'rm -rf "$BUILD_ROOT"' EXIT
mkdir -p release "$BUILD_ROOT/root/Applications/SibKa PdM"
"$PYTHON_BIN" -m venv "$BUILD_ROOT/venv"
"$BUILD_ROOT/venv/bin/python" -m pip install -r requirements.txt 'PyInstaller==6.22.3'
"$BUILD_ROOT/venv/bin/python" -m PyInstaller \
 --noconfirm --clean --onedir --name sibka-pdm \
 --paths . --distpath "$BUILD_ROOT/dist" --workpath "$BUILD_ROOT/work" --specpath "$BUILD_ROOT" \
 --add-data "$PWD/pdm/templates:pdm/templates" --add-data "$PWD/pdm/static:pdm/static" \
 packaging/macos/launcher.py
DEST="$BUILD_ROOT/root/Applications/SibKa PdM"
cp -R "$BUILD_ROOT/dist/sibka-pdm" "$DEST/runtime"
cp 'packaging/macos/Start SibKa PdM.command' "$DEST/"
cp docs/lab8/INSTALL_RU.md "$DEST/Инструкция.txt"
mkdir -p "$DEST/database"
cp database/v2/SibKa_PdM_v2.sql database/v2/Lab7_connection_checks.sql "$DEST/database/"
chmod 755 "$DEST/Start SibKa PdM.command"
"$DEST/runtime/sibka-pdm" --self-test
pkgbuild --root "$BUILD_ROOT/root" --identifier ru.sibka.pdm --version "$VERSION" \
 --install-location / --ownership recommended "$BUILD_ROOT/component.pkg"
productbuild --package "$BUILD_ROOT/component.pkg" \
 "release/SibKa-PdM-$VERSION-macOS-$ARCH.pkg"
pkgutil --check-signature "release/SibKa-PdM-$VERSION-macOS-$ARCH.pkg" || true
shasum -a 256 "release/SibKa-PdM-$VERSION-macOS-$ARCH.pkg"

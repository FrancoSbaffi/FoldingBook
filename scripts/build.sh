#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$PWD/Package.swift" ]; then
    PROJECT_DIR="$PWD"
else
    PROJECT_DIR="/Users/francosbaffidevgmail.com/Desktop/Cosas/WEBs/FoldingBook"
fi
cd "$PROJECT_DIR"

echo "==> Compiling FoldingBook with Swift..."
swift build -c release

BUILD_DIR="$(swift build -c release --show-bin-path)"
APP_BUNDLE="$PROJECT_DIR/dist/FoldingBook.app"

echo "==> Packaging $APP_BUNDLE..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/FoldingBook" "$APP_BUNDLE/Contents/MacOS/FoldingBook"
chmod +x "$APP_BUNDLE/Contents/MacOS/FoldingBook"
cp "$PROJECT_DIR/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

echo "==> Cleaning extended attributes..."
xattr -rd com.apple.FinderInfo "$APP_BUNDLE" 2>/dev/null || true
xattr -cr "$APP_BUNDLE" 2>/dev/null || true

echo "==> Signing application with persistent designated requirement..."
/usr/bin/codesign --force --sign - --identifier "com.foldingbook.app" -r='designated => identifier "com.foldingbook.app"' "$APP_BUNDLE"

echo "==> FoldingBook.app successfully built and packaged at:"
echo "    $APP_BUNDLE"

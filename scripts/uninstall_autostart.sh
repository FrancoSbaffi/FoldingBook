#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

PLIST_PATH="$HOME/Library/LaunchAgents/com.foldingbook.app.plist"

echo "==> Stopping FoldingBook service..."
launchctl bootout "gui/$(id -u)/com.foldingbook.app" 2>/dev/null || true
if [ -f "$PLIST_PATH" ]; then
    launchctl unload "$PLIST_PATH" >/dev/null 2>&1 || true
    rm -f "$PLIST_PATH"
    echo "==> LaunchAgent removed."
fi

pkill -x FoldingBook >/dev/null 2>&1 || true

if [ -d "/Applications/FoldingBook.app" ]; then
    rm -rf "/Applications/FoldingBook.app"
    echo "==> /Applications/FoldingBook.app removed."
fi

echo "==> FoldingBook has been completely uninstalled."

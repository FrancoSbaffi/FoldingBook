#!/usr/bin/env bash
set -euo pipefail

PLIST_PATH="$HOME/Library/LaunchAgents/com.foldingbook.app.plist"

echo "==> Desactivando servicio de FoldingBook..."
if [ -f "$PLIST_PATH" ]; then
    launchctl unload "$PLIST_PATH" >/dev/null 2>&1 || true
    rm -f "$PLIST_PATH"
    echo "==> LaunchAgent eliminado."
fi

pkill -x FoldingBook >/dev/null 2>&1 || true

if [ -d "/Applications/FoldingBook.app" ]; then
    rm -rf "/Applications/FoldingBook.app"
    echo "==> /Applications/FoldingBook.app eliminado."
fi

echo "==> FoldingBook ha sido desinstalado completamente."

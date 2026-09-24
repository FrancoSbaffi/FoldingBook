#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

echo "==> 1. Compiling FoldingBook..."
"$SCRIPT_DIR/build.sh"

echo "==> 2. Installing to /Applications/FoldingBook.app..."
pkill -x FoldingBook >/dev/null 2>&1 || true
rm -rf "/Applications/FoldingBook.app"
cp -R "$PROJECT_DIR/dist/FoldingBook.app" "/Applications/FoldingBook.app"

PLIST_PATH="$HOME/Library/LaunchAgents/com.foldingbook.app.plist"
mkdir -p "$HOME/Library/LaunchAgents"

echo "==> 3. Configuring autostart service (LaunchAgent) at $PLIST_PATH..."
cat <<EOF > "$PLIST_PATH"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.foldingbook.app</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Applications/FoldingBook.app/Contents/MacOS/FoldingBook</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ProcessType</key>
    <string>Interactive</string>
    <key>StandardOutPath</key>
    <string>/tmp/foldingbook.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/foldingbook_err.log</string>
</dict>
</plist>
EOF

echo "==> 4. Activating service in launchd..."
launchctl unload "$PLIST_PATH" >/dev/null 2>&1 || true
launchctl load -w "$PLIST_PATH"

echo "==> Done! FoldingBook is installed and configured to run 100% of the time."
echo "    - Automatically restarts if closed or upon system reboot."
echo "    - Remember to grant Screen Recording permission in System Settings if running for the first time."

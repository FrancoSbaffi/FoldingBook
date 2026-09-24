#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$PWD/Package.swift" ]; then
    PROJECT_DIR="$PWD"
else
    PROJECT_DIR="/Users/francosbaffidevgmail.com/Desktop/Cosas/WEBs/FoldingBook"
fi
cd "$PROJECT_DIR"

echo "==> 1. Compilando FoldingBook..."
"$SCRIPT_DIR/build.sh"

echo "==> 2. Instalando en /Applications/FoldingBook.app..."
pkill -x FoldingBook >/dev/null 2>&1 || true
rm -rf "/Applications/FoldingBook.app"
cp -R "$PROJECT_DIR/dist/FoldingBook.app" "/Applications/FoldingBook.app"

PLIST_PATH="$HOME/Library/LaunchAgents/com.foldingbook.app.plist"
mkdir -p "$HOME/Library/LaunchAgents"

echo "==> 3. Configurando servicio de inicio automático (LaunchAgent) en $PLIST_PATH..."
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

echo "==> 4. Activando servicio en launchd..."
launchctl unload "$PLIST_PATH" >/dev/null 2>&1 || true
launchctl load -w "$PLIST_PATH"

echo "==> ¡Listo! FoldingBook ha sido instalado y configurado para ejecutarse el 100% del tiempo."
echo "    - Se reiniciará automáticamente si se cierra o si reinicias tu Mac."
echo "    - Recuerda conceder permiso de Grabación de Pantalla en Ajustes del Sistema si es la primera vez."

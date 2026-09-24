#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$PWD/Package.swift" ]; then
    PROJECT_DIR="$PWD"
else
    PROJECT_DIR="/Users/francosbaffidevgmail.com/Desktop/Cosas/WEBs/FoldingBook"
fi
cd "$PROJECT_DIR"

MODE="${1:-run}"

case "$MODE" in
    run|--build|--probe|--preview|--verify|--test) ;;
    *)
        echo "Usage: $0 [run|--build|--probe|--preview|--verify|--test]" >&2
        exit 1
        ;;
esac

if [ "$MODE" = "--probe" ]; then
    swift run FoldingBook --probe
    exit 0
fi

if [ "$MODE" = "--test" ]; then
    swift run FoldingBookChecks
    exit 0
fi

if [ "$MODE" = "--preview" ]; then
    swift run FoldingBook --preview
    exit 0
fi

"$SCRIPT_DIR/build.sh"

if [ "$MODE" = "--build" ]; then
    exit 0
fi

echo "==> Terminating previous FoldingBook instances if any..."
pkill -x FoldingBook >/dev/null 2>&1 || true

echo "==> Launching FoldingBook..."
/usr/bin/open -n "$PROJECT_DIR/dist/FoldingBook.app"

if [ "$MODE" = "--verify" ]; then
    sleep 1
    if pgrep -x FoldingBook >/dev/null; then
        echo "==> FoldingBook is running in background (PID: $(pgrep -x FoldingBook))."
    else
        echo "==> Error: FoldingBook failed to launch."
        exit 1
    fi
fi

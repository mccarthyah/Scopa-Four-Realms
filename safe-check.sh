#!/bin/sh
# safe-check.sh — prove Scopa: Four Realms is healthy WITHOUT opening a window.
#
# Nothing here creates a GPU context or a window, so it cannot lock up a VM the
# way a renderer can. Run this first; if it passes, the game logic, the asset
# pipeline and the layout are all fine and any remaining problem is in the
# display/render layer.
#
#   ./safe-check.sh            run the checks
#   ./safe-check.sh log        show the log left by the last (frozen) run
#
# Usage notes: pass the Godot binary if it is not on PATH:
#   GODOT=/path/to/godot ./safe-check.sh

set -u
GODOT="${GODOT:-godot}"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ---- locate the retained legacy user-data folder ---------
case "$(uname -s)" in
  Darwin) BASE="$HOME/Library/Application Support/Godot/app_userdata";;
  Linux)  BASE="$HOME/.local/share/godot/app_userdata";;
  *)      BASE="${APPDATA:-%APPDATA%}\\Godot\\app_userdata";;
esac
LOGDIR=""
for d in "$BASE"/Scopa*; do
  [ -d "$d" ] && LOGDIR="$d/logs"
done

if [ "${1:-}" = "log" ]; then
  if [ -n "$LOGDIR" ] && [ -f "$LOGDIR/godot.log" ]; then
    echo "--- $LOGDIR/godot.log (tail) ---"
    tail -n 200 "$LOGDIR/godot.log"
    echo
    echo "If the last line is a 'heartbeat' with a 'stage=' value, the game was"
    echo "alive but stuck in that stage. If there is no heartbeat at all, it died"
    echo "before the main loop — that is a renderer/display failure, not a script one."
  else
    echo "No log found under: $BASE"
    echo "Godot keeps older runs as godot<timestamp>.log in the same folder."
  fi
  exit 0
fi

if ! command -v "$GODOT" >/dev/null 2>&1; then
  echo "Godot binary not found: $GODOT"
  echo "Set it explicitly, e.g.:  GODOT=~/Godot_v4.7.2-stable_linux.x86_64 ./safe-check.sh"
  exit 2
fi

echo "Godot: $("$GODOT" --version)"
echo "Project: $PROJECT_DIR"
echo

echo "[1/3] Importing assets (headless — no window, no GPU context)"
"$GODOT" --headless --path "$PROJECT_DIR" --import >/tmp/scopa_import.log 2>&1
# A Godot built without fontconfig logs a capability notice on every font load.
# It is not an import failure, and treating it as one makes the check impossible
# to pass with a headless/custom build.
IMPORT_ERRS=$(grep -E "ERROR|Parse Error" /tmp/scopa_import.log | grep -v "compiled without fontconfig")
if [ -n "$IMPORT_ERRS" ]; then
  echo "  FAILED — first errors:"
  printf '%s\n' "$IMPORT_ERRS" | head -10
  echo "  (full log: /tmp/scopa_import.log)"
  exit 1
fi
echo "  ok — assets imported, no errors"

echo "[2/3] Booting the game headless for ~5 seconds"
"$GODOT" --headless --path "$PROJECT_DIR" --quit-after 600 >/tmp/scopa_boot.log 2>&1
if grep -qE "SCRIPT ERROR|Parse Error" /tmp/scopa_boot.log; then
  echo "  FAILED — first errors:"
  grep -E "SCRIPT ERROR|Parse Error" /tmp/scopa_boot.log | head -10
  exit 1
fi
grep -E "^\[scopa\]" /tmp/scopa_boot.log | head -12 | sed 's/^/  /'
echo "  ok — booted, main loop running"

echo "[3/3] Running the full self-test (rules, AI, layout, save/resume)"
"$GODOT" --headless --path "$PROJECT_DIR" -- --audit >/tmp/scopa_audit.log 2>&1
if grep -q "failures=0" /tmp/scopa_audit.log; then
  CHECKS=$(grep -c "ok  " /tmp/scopa_audit.log)
  echo "  ok — $CHECKS checks passed, 0 failures"
else
  echo "  FAILED:"
  grep -E "FAIL" /tmp/scopa_audit.log | head -10
  exit 1
fi

echo
echo "ALL HEADLESS CHECKS PASSED."
echo "This says nothing about rendering: no GPU context was created."
echo "To see the log from the last windowed run:  ./safe-check.sh log"

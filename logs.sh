#!/bin/sh
# Scopa: Four Realms — find, print and package the game's log.
#   ./logs.sh          show the log folder and the latest 120 lines
#   ./logs.sh copy     copy the log folder path for pasting into a crash report
set -e

case "$(uname -s)" in
  Darwin) BASE="$HOME/Library/Application Support/Godot/app_userdata";;
  Linux)  BASE="$HOME/.local/share/godot/app_userdata";;
  *)      BASE="${APPDATA:-%APPDATA%}\\Godot\\app_userdata";;
esac

# Godot sanitises the project name for the folder: 'Scopa: Four Realms' becomes
# 'Scopa- Four Realms'. Match on a prefix so this keeps working either way.
DIR=""
for d in "$BASE"/Scopa*; do
  [ -d "$d" ] && DIR="$d"
done

if [ -z "$DIR" ]; then
  echo "No Scopa user-data folder found under:"
  echo "  $BASE"
  echo
  echo "That means the game has not run yet (or ran without file logging)."
  exit 1
fi

echo "User data: $DIR"
echo "Logs:      $DIR/logs"
echo

if [ "$1" = "copy" ]; then
  printf '%s' "$DIR/logs"
  exit 0
fi

LOG="$DIR/logs/godot.log"
if [ -f "$LOG" ]; then
  echo "--- last 120 lines of godot.log (the crash is at the bottom) ---"
  tail -n 120 "$LOG"
else
  echo "No godot.log yet. Older sessions are kept as godot<timestamp>.log:"
  ls -1t "$DIR/logs" 2>/dev/null | head -5
fi

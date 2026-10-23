#!/bin/sh
# Opens the game on macOS/Linux. Pass res://debug.tscn for the debug map.
# Set GODOT to override the Godot binary path.
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
exec "$GODOT" --path "$(dirname "$0")" "$@"

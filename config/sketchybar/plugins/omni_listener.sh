#!/bin/bash

# Sketchybar script agent: renders once, then follows OmniWM's event stream.
# Resubscribes in a loop so OmniWM restarts and sleep/wake recover on their own.

PLUGIN_DIR="$(cd "$(dirname "$0")" && pwd)"
OMNIWMCTL="${OMNIWMCTL_BIN:-omniwmctl}"

"$PLUGIN_DIR/workspaces.sh" &

while true; do
  "$OMNIWMCTL" subscribe active-workspace,windows-changed,display-changed,layout-changed 2>/dev/null |
    while IFS= read -r _; do
      sleep 0.05
      "$PLUGIN_DIR/workspaces.sh"
    done
  sleep 1
done

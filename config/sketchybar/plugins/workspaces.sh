#!/bin/bash

# Render the workspace pills from OmniWM's IPC. Fixed set ws.1..ws.5; extend
# the two loops here when more workspaces are added in OmniWM.

SB="${SKETCHYBAR_CLIENT:-sketchybar}"
OMNIWMCTL="${OMNIWMCTL_BIN:-omniwmctl}"
JQ="${JQ_BIN:-jq}"
[ -n "$SB" ] || exit 0

WS_COLOR=0xffe8e0d0
WS_DIM=0x80e8e0d0
WS_GHOST=0x50e8e0d0
BG_DARK=0xff22252b
BG_GLOW=0x33e8e0d0

json="$($OMNIWMCTL query workspaces --format json 2>/dev/null)" || exit 0

args=()
for i in 1 2 3 4 5; do
  row="$($JQ -c --argjson n "$i" '.result.payload.workspaces[]? | select(.number == $n)' <<<"$json")"
  if [ -z "$row" ]; then
    args+=(--set "ws.$i" drawing=off)
    continue
  fi
  icon="$($JQ -r '.displayName // .rawName' <<<"$row")"
  focused="$($JQ -r '.isFocused == true' <<<"$row")"
  visible="$($JQ -r '.isVisible == true' <<<"$row")"
  args+=(--set "ws.$i" drawing=on icon="$icon")
  if [ "$focused" = "true" ]; then
    args+=(background.color="$WS_COLOR" icon.color="$BG_DARK")
  elif [ "$visible" = "true" ]; then
    args+=(background.color="$BG_GLOW" icon.color="$WS_COLOR")
  else
    args+=(background.color=0x00000000 icon.color="$WS_GHOST")
  fi
done
"$SB" "${args[@]}" >/dev/null

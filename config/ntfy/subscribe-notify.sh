#!/bin/zsh
# Subscribes to an ntfy topic (arg 1) and fires a macOS notification per message.
# Token lives outside this repo — see ~/.config/ntfy/token.env (untracked).
set -a
[ -f "$HOME/.config/ntfy/token.env" ] && source "$HOME/.config/ntfy/token.env"
set +a

exec ntfy subscribe --config "$HOME/.config/ntfy/client.yml" --token "$NTFY_TOKEN" "$1" \
  'osascript -e "display notification \"$NTFY_MESSAGE\" with title \"${NTFY_TITLE:-ntfy}\""'

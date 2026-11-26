np_bin=${NP_BIN:-$HOME/.local/bin/np}
status=""
query=""

if ! items=$("$np_bin" item list --format json 2>/dev/null); then
  echo "np could not list your vault. Run: np unlock" >&2
  exit 1
fi

copy() {
  if "$np_bin" item get "$1" --field "$2" --copy >/dev/null 2>&1; then
    status="Copied $2 from $3"
  else
    status="Could not copy $2 from $3"
  fi
}

# Values of these fields are shown in the field menu; every other field is masked.
visible='["username", "url", "email", "cardholderName", "expiryDate"]'

while true; do
  picked=$(
    jq -r '.[] | [.id, .type, .title, (.username // ""), (.url // "")] | @tsv' <<<"$items" |
      fzf --delimiter=$'\t' --with-nth=2.. --tabstop=2 \
        --prompt='NordPass> ' \
        --header="enter fields · ctrl-p copy password · ctrl-u copy username · esc quit${status:+
$status}" \
        --print-query --query="$query" --expect=ctrl-p,ctrl-u
  ) || exit 0

  query=$(sed -n 1p <<<"$picked")
  key=$(sed -n 2p <<<"$picked")
  row=$(sed -n 3p <<<"$picked")
  [ -n "$row" ] || continue
  id=$(cut -f1 <<<"$row")
  title=$(cut -f3 <<<"$row")

  case $key in
    ctrl-p) copy "$id" password "$title"; continue ;;
    ctrl-u) copy "$id" username "$title"; continue ;;
  esac

  if ! item=$("$np_bin" item get "$id" --format json 2>/dev/null); then
    status="Could not read $title. Is the vault locked? Run: np unlock"
    continue
  fi
  field=$(
    jq -r --argjson visible "$visible" '
      to_entries[]
      | select(.key | IN("id", "type", "title") | not)
      | [.key, (if (.key | IN($visible[])) then (.value | tostring) else "••••••••" end)]
      | @tsv' <<<"$item" |
      fzf --delimiter=$'\t' --tabstop=2 --prompt="$title> " --header='enter copy · esc back'
  ) || continue
  copy "$id" "$(cut -f1 <<<"$field")" "$title"
done

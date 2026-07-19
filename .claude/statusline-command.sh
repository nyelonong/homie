#!/usr/bin/env bash
input=$(cat)
# Cache the official rate limits for agent sessions (usage-threshold rule).
# Only write when present so a limit-less render never clobbers a good cache.
rl=$(echo "$input" | jq -c '.rate_limits | select(. != null) | . + {cached_at: now}' 2>/dev/null)
# Atomic write: a concurrent render must never expose a half-written cache to
# the usage-threshold automation that reads this file.
if [ -n "$rl" ]; then
  printf '%s\n' "$rl" > "$HOME/.claude/rate-limits-cache.json.tmp.$$" &&
    mv "$HOME/.claude/rate-limits-cache.json.tmp.$$" "$HOME/.claude/rate-limits-cache.json"
fi
# Git status
git_info=""
cwd=$(echo "$input" | jq -r '.workspace.current_dir // empty')
if [ -n "$cwd" ]; then
  branch=$(git -C "$cwd" --no-optional-locks rev-parse --abbrev-ref HEAD 2>/dev/null)
  if [ -n "$branch" ]; then
    dirty=$(git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    if [ "$dirty" -gt 0 ]; then
      git_info=$(printf " \033[33m(%s *%s)\033[0m" "$branch" "$dirty")
    else
      git_info=$(printf " \033[32m(%s)\033[0m" "$branch")
    fi
  fi
fi
# Active skills / MCP / plugins (second line).
#   plugins: enabledPlugins=true across user+project+local settings (hook plugins
#            like caveman/ponytail are active every prompt yet never appear in the
#            transcript, so this must come from config, not usage).
#   mcp:     configured servers (~/.claude.json + project .mcp.json) UNION servers
#            actually called this session (claude.ai connectors live in no local
#            config, so usage is the only way to see them).
#   skills:  Skill-tool invocations this session (everything *available* is ~100
#            names — unrenderable; usage is the meaningful "active" set).
# Transcript-derived parts are cached per session keyed by file size, so a render
# only re-parses after the transcript grew.
# ponytail: full re-parse on growth; switch to byte-offset incremental if huge
# transcripts ever make this slow.
transcript=$(echo "$input" | jq -r '.transcript_path // empty')
proj=$(echo "$input" | jq -r '.workspace.project_dir // empty')
used_skills="" used_mcp=""
if [ -f "$transcript" ]; then
  cache="$HOME/.claude/statusline-usage-cache/$(basename "$transcript" .jsonl).json"
  mkdir -p "${cache%/*}"
  size=$(stat -f%z "$transcript" 2>/dev/null || stat -c%s "$transcript" 2>/dev/null)
  if [ "$size" != "$(jq -r '.size // -1' "$cache" 2>/dev/null)" ]; then
    # -R + fromjson? survives a partially written trailing line.
    jq -R -n -c --argjson size "${size:-0}" '
      [inputs | fromjson? | select(.type=="assistant")
       | .message.content[]? | select(.type=="tool_use")] as $t
      | {size: $size,
         skills: ([$t[] | select(.name=="Skill") | .input.skill? // empty] | unique),
         mcp: ([$t[] | .name | select(startswith("mcp__"))
               | ltrimstr("mcp__") | split("__")[0]] | unique)}
    ' "$transcript" > "$cache.tmp.$$" 2>/dev/null && mv "$cache.tmp.$$" "$cache" || rm -f "$cache.tmp.$$"
  fi
  used_skills=$(jq -r '.skills[]?' "$cache" 2>/dev/null)
  used_mcp=$(jq -r '.mcp[]?' "$cache" 2>/dev/null)
fi
settings_files=()
for f in "$HOME/.claude/settings.json" "$proj/.claude/settings.json" "$proj/.claude/settings.local.json"; do
  [ -f "$f" ] && settings_files+=("$f")
done
plugins=""
if [ ${#settings_files[@]} -gt 0 ]; then
  plugins=$(jq -rs 'map(.enabledPlugins // {}) | add // {}
    | to_entries[] | select(.value) | .key | split("@")[0]' "${settings_files[@]}" 2>/dev/null | sort -u)
fi
mcp_cfg=$(jq -r '.mcpServers // {} | keys[]' "$HOME/.claude.json" 2>/dev/null)
[ -f "$proj/.mcp.json" ] && mcp_cfg="$mcp_cfg
$(jq -r '.mcpServers // {} | keys[]' "$proj/.mcp.json" 2>/dev/null)"
mcp=$(printf '%s\n%s\n' "$mcp_cfg" "$used_mcp" | grep -v '^$' | sort -u)
# First 4 names + "+N" overflow, comma-joined.
cap_list() { awk 'NR<=4{s=s (NR>1?",":"") $0} NR>4{n++} END{if(n)s=s "+" n; print s}'; }
usage_line=""
s=$(printf '%s\n' "$used_skills" | grep -v '^$' | sed 's/.*://' | sort -u | cap_list)
m=$(printf '%s\n' "$mcp" | grep -v '^$' | cap_list)
p=$(printf '%s\n' "$plugins" | grep -v '^$' | cap_list)
[ -n "$s" ] && usage_line="$usage_line$(printf ' \033[2mskills:\033[0m%s' "$s")"
[ -n "$m" ] && usage_line="$usage_line$(printf ' \033[2mmcp:\033[0m%s' "$m")"
[ -n "$p" ] && usage_line="$usage_line$(printf ' \033[2mplugins:\033[0m%s' "$p")"
# Model
model=$(echo "$input" | jq -r '.model.display_name // empty')
# Effort
effort=$(echo "$input" | jq -r '.effort.level // empty')
effort_str=""
[ -n "$effort" ] && effort_str=" [$effort]"
# Context window
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
ctx_str=""
[ -n "$used_pct" ] && ctx_str=" ctx:$(printf '%.0f' "$used_pct")%"
# Rate limits
five=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
five_resets=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
week=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
rate_str=""
if [ -n "$five" ]; then
  rate_str=" 5h:$(printf '%.0f' "$five")%"
  if [ -n "$five_resets" ]; then
    now=$(date +%s)
    secs_left=$(( five_resets - now ))
    if [ "$secs_left" -gt 0 ]; then
      mins_left=$(( secs_left / 60 ))
      if [ "$mins_left" -ge 60 ]; then
        reset_label="$(( mins_left / 60 ))h$(( mins_left % 60 ))m"
      else
        reset_label="${mins_left}m"
      fi
      rate_str="$rate_str(resets ${reset_label})"
    fi
  fi
fi
[ -n "$week" ] && rate_str="$rate_str 7d:$(printf '%.0f' "$week")%"
printf "\033[36m%s\033[0m%s%s%s\n" \
  "${model}${effort_str}" \
  "$ctx_str" \
  "$rate_str" \
  "$git_info"
[ -n "$usage_line" ] && printf '%s\n' "${usage_line# }"

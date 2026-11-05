#!/bin/bash
# LeakWatch - DNS leak test for macOS.
# Resolves unique names through the system resolver, then asks bash.ws which
# DNS servers made those lookups. Results go to ~/.leakwatch/leakwatch.log and
# ~/.leakwatch/status.json (read by the LeakWatch menu bar app).
#
# Settings live in ~/.leakwatch/config.sh (created by install.sh).
# Env: LEAKWATCH_QUIET=1 -> no notifications/sounds and no waiting for network.

DIR="$HOME/.leakwatch"
CONFIG="$DIR/config.sh"
LOG="$DIR/leakwatch.log"
STATUS_FILE="$DIR/status.json"
API="https://bash.ws"

# Defaults (override in config.sh)
ALLOWED_COUNTRIES=()     # empty = do not check for "unwanted country"
ALERT_WORDS=()           # e.g. ("Russia" "ru" "Moscow"); 2-letter words match the country code
LEAK_SOUND="Basso"
CRITICAL_SOUND="Hero"
CRITICAL_REPEAT=3
[ -f "$CONFIG" ] && source "$CONFIG"

mkdir -p "$DIR"
JQ=$(command -v jq || echo /usr/bin/jq)
ts() { date '+%Y-%m-%d %H:%M:%S'; }
quiet() { [ "${LEAKWATCH_QUIET:-0}" = "1" ]; }
notify() { quiet || osascript -e "display notification \"$2\" with title \"$1\"" >/dev/null 2>&1; }
play() {
  quiet && return
  local f="$1"; [ -f "$f" ] || f="/System/Library/Sounds/$1.aiff"
  for _ in $(seq 1 "${2:-1}"); do afplay "$f" 2>/dev/null; done
}
save_status() { # $1=status $2=message $3=json $4=flagged lines
  "$JQ" -n --arg s "$1" --arg m "$2" --arg t "$(ts)" --argjson j "${3:-[]}" --arg f "$4" \
    '{time:$t, epoch:(now|floor), status:$s, message:$m,
      ip:($j|map(select(.type=="ip"))|.[0]), dns:($j|map(select(.type=="dns"))),
      flagged:($f|split("\n")|map(select(length>0)))}' > "$STATUS_FILE.tmp" && mv "$STATUS_FILE.tmp" "$STATUS_FILE"
}
fail() { echo "[$(ts)] ERROR: $1" >> "$LOG"; save_status ERROR "$1"; exit 1; }

# Wait for network/VPN after login or wake (up to ~2 min)
if ! quiet; then
  for _ in $(seq 1 12); do curl -fsS --max-time 5 -o /dev/null "$API/id" && break; sleep 10; done
fi

id=$(curl -fsS --max-time 15 "$API/id") || fail "cannot reach bash.ws (offline?)"
for i in $(seq 1 10); do ping -c 1 -t 1 "$i.$id.bash.ws" >/dev/null 2>&1 & done; wait
json=$(curl -fsS --max-time 15 "$API/dnsleak/test/$id?json") || fail "result fetch failed"

to_json() { if [ $# -eq 0 ]; then echo '[]'; else printf '%s\n' "$@" | "$JQ" -R . | "$JQ" -sc .; fi; }
allowed=$(to_json "${ALLOWED_COUNTRIES[@]}")
alertw=$(to_json "${ALERT_WORDS[@]}")
line='"\(.type | ascii_upcase) \(.ip) [\(.country_name)] \(.asn // "")"'

# LEAK: public IP or DNS server in a country not on the allowed list
bad=$(echo "$json" | "$JQ" -r --argjson ok "$allowed" \
  ".[] | select(\$ok | length > 0) | select((.type==\"ip\" or .type==\"dns\") and ((.country_name // \"\") as \$c | \$ok | index(\$c) | not)) | $line")

# CRITICAL: alert word found in country name / operator, or 2-letter word == country code
crit=$(echo "$json" | "$JQ" -r --argjson aw "$alertw" \
  ".[] | select(.type==\"ip\" or .type==\"dns\")
       | ([.country_name, .asn, .org] | map(. // \"\" | ascii_downcase) | join(\" \")) as \$t
       | ((.country // \"\") | ascii_downcase) as \$cc
       | select(any(\$aw[]; ascii_downcase as \$w |
           if (\$w | length) == 2 then \$cc == \$w else (\$t | contains(\$w)) end))
       | $line")

{
  echo "===== $(ts) ====="
  echo "$json" | "$JQ" -r '.[] | select(.type=="ip")  | "Your IP:   \(.ip)  [\(.country_name)] \(.asn // "")"'
  echo "DNS servers seen: $(echo "$json" | "$JQ" '[.[] | select(.type=="dns")] | length')"
  echo "$json" | "$JQ" -r '.[] | select(.type=="dns") | "  - \(.ip)  [\(.country_name)] \(.asn // "")"'
  if [ -n "$crit" ]; then echo "STATUS: CRITICAL - alert location detected:"; echo "$crit" | sed 's/^/  !!! /'
  elif [ -n "$bad" ]; then echo "STATUS: LEAK - unwanted location:"; echo "$bad" | sed 's/^/  ! /'
  else echo "STATUS: OK (all locations allowed)"; fi
  echo
} | tee -a "$LOG"

if [ -n "$crit" ]; then save_status CRITICAL "Alert location detected" "$json" "$crit"
elif [ -n "$bad" ]; then save_status LEAK "Unwanted location" "$json" "$bad"
else save_status OK "All locations allowed" "$json"; fi

if [ -n "$crit" ]; then
  msg=$(echo "$crit" | head -3 | sed 's/"/\\"/g' | tr '\n' ' ')
  notify "LeakWatch: real location exposed" "$msg"
  quiet || nohup osascript -e "display alert \"LeakWatch: real location exposed\" message \"$msg\" as critical" >/dev/null 2>&1 &
  play "$CRITICAL_SOUND" "$CRITICAL_REPEAT"
elif [ -n "$bad" ]; then
  notify "LeakWatch: DNS leak detected" "$(echo "$bad" | head -3 | sed 's/"/\\"/g' | tr '\n' ' ')"
  play "$LEAK_SOUND" 1
fi
exit 0

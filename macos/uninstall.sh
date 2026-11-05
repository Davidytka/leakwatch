#!/bin/bash
# Removes LeakWatch from macOS. Messages: Russian first, then English.
say() { printf '%s\n\033[2m%s\033[0m\n' "$1" "$2"; }

for job in test app; do
  launchctl bootout "gui/$(id -u)/com.leakwatch.$job" 2>/dev/null
  rm -f "$HOME/Library/LaunchAgents/com.leakwatch.$job.plist"
done
pkill -x LeakWatch 2>/dev/null
rm -rf "$HOME/Applications/LeakWatch.app"
defaults delete com.leakwatch.app 2>/dev/null

say "Удалить также настройки и журнал в ~/.leakwatch? [y/N]" "Also delete settings and log in ~/.leakwatch? [y/N]"
read -r -p "> " a
case "$a" in y*|Y*|д*|Д*) rm -rf "$HOME/.leakwatch"; say "Настройки и журнал удалены." "Settings and log deleted." ;; esac
say "LeakWatch удалён." "LeakWatch removed."

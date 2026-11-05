#!/bin/bash
# Removes LeakWatch from macOS.
for job in test app; do
  launchctl bootout "gui/$(id -u)/com.leakwatch.$job" 2>/dev/null
  rm -f "$HOME/Library/LaunchAgents/com.leakwatch.$job.plist"
done
pkill -x LeakWatch 2>/dev/null
rm -rf "$HOME/Applications/LeakWatch.app"
defaults delete com.leakwatch.app 2>/dev/null

read -r -p "Also delete settings and log in ~/.leakwatch? [y/N] " a
case "$a" in [yY]*) rm -rf "$HOME/.leakwatch"; echo "Settings and log deleted." ;; esac
echo "LeakWatch removed."

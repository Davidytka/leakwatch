#!/bin/bash
# LeakWatch installer for macOS.
# Installs to ~/.leakwatch, builds ~/Applications/LeakWatch.app, and sets up
# an hourly test + the menu bar app at login (launchd, no admin rights needed).
set -e

SRC="$(cd "$(dirname "$0")" && pwd)"
DIR="$HOME/.leakwatch"
APP="$HOME/Applications/LeakWatch.app"
LA="$HOME/Library/LaunchAgents"
# Every message is shown in Russian first, then in English (dimmed).
title() { printf '\n\033[1m%s\033[0m\n\033[2m%s\033[0m\n' "$1" "$2"; }
say()   { printf '%s\n\033[2m%s\033[0m\n' "$1" "$2"; }
ask()   { say "$2" "$3"; read -r -p "> " "$1"; }
to_array() { # "a, b ,c" -> "a" "b" "c"
  local out="" item
  IFS=',' read -ra parts <<< "$1"
  for item in "${parts[@]}"; do
    item=$(echo "$item" | tr -d '"' | sed 's/^ *//; s/ *$//')
    [ -n "$item" ] && out+="\"$item\" "
  done
  echo "$out"
}

# ---- checks ------------------------------------------------------------------
[ "$(uname)" = "Darwin" ] || { say "Этот установщик только для macOS." "This installer is for macOS."; exit 1; }
if ! command -v jq >/dev/null; then
  say "Нужна программа jq (встроена в macOS 15+). Установи её: brew install jq" \
      "jq is required (built into macOS 15+). Install it with: brew install jq"; exit 1
fi
if ! command -v swiftc >/dev/null; then
  say "Для сборки приложения нужны Apple Command Line Tools." "Apple Command Line Tools are needed to build the app."
  say "Выполни:  xcode-select --install   и запусти установщик ещё раз." \
      "Run:  xcode-select --install   then run this installer again."; exit 1
fi

title "LeakWatch — установка" "LeakWatch installer"

mkdir -p "$DIR" "$HOME/Applications" "$LA"
cp "$SRC/leakwatch.sh" "$SRC/uninstall.sh" "$DIR/"
chmod +x "$DIR/leakwatch.sh" "$DIR/uninstall.sh"

# ---- settings ----------------------------------------------------------------
if [ -f "$DIR/config.sh" ]; then
  title "Оставляю твои прежние настройки: $DIR/config.sh" "Keeping your existing settings: $DIR/config.sh"
else
  title "Шаг 1. Подключи VPN и нажми Enter." "Step 1. Connect your VPN now, then press Enter."
  read -r -p "> " _
  say "Провожу первую проверку (несколько секунд)..." "Running a first test (takes a few seconds)..."
  LEAKWATCH_QUIET=1 "$DIR/leakwatch.sh" >/dev/null 2>&1 || true
  seen=$(jq -r '[.ip, .dns[]?] | map(select(. != null) | .country_name) | unique | join(", ")' "$DIR/status.json" 2>/dev/null || true)

  title "Шаг 2. Разрешённые страны (где находятся серверы твоего VPN)." \
        "Step 2. Allowed countries (where your VPN servers are)."
  say "Названия — по-английски, как их пишет bash.ws (например, 'United States', 'Russian Federation')." \
      "Names must match how bash.ws writes them (e.g. 'United States', 'Russian Federation')."
  if [ -n "$seen" ]; then
    say "Сейчас видны страны: $seen" "Countries seen right now: $seen"
    ask ans "Нажми Enter, чтобы разрешить именно их, или впиши свой список через запятую:" \
            "Press Enter to allow exactly these, or type your own comma-separated list:"
    allowed="${ans:-$seen}"
  else
    say "Не удалось провести проверку (нет интернета?)." "Could not run the test (offline?)."
    ask allowed "Впиши разрешённые страны через запятую (например: Netherlands, Sweden) или оставь пустым:" \
                "Type allowed countries, comma-separated (e.g. Netherlands, Sweden), or leave empty:"
  fi

  title "Шаг 3. Твоя реальная страна." "Step 3. Your real country."
  say "Если она хоть раз появится в проверке, LeakWatch поднимет красную тревогу: окно и звук." \
      "If it EVER shows up in a test, LeakWatch raises a red alert with a pop-up and sound."
  ask home "Название страны латиницей (например: Russia, Iran, China, Turkey) или оставь пустым:" \
           "Country name (e.g. Russia, Iran, China, Turkey) or leave empty:"
  ask extra "Необязательно: другие слова-тревоги — города или провайдеры, через запятую:" \
            "Optional extra alert words - cities or ISP names, comma-separated:"

  cat > "$DIR/config.sh" <<EOF
# LeakWatch settings. Edit, save - the next test uses them. No restart needed.

# Countries where your VPN servers / DNS are allowed to be (exact bash.ws names).
# Public IP or DNS server elsewhere => orange "Leak" + notification.
# Empty () = skip this check.
ALLOWED_COUNTRIES=($(to_array "$allowed"))

# Words that mean "my real location is exposed" => red alert, pop-up, loud sound.
# Matched case-insensitively in country name and network operator name.
# A 2-letter word (e.g. "ru") is matched against the country code.
ALERT_WORDS=($(to_array "$home, $extra"))

# Sounds: Basso Blow Bottle Frog Funk Glass Hero Morse Ping Pop Purr Sosumi
# Submarine Tink - or a full path to your own .aiff/.mp3/.wav file.
LEAK_SOUND="Basso"
CRITICAL_SOUND="Hero"
CRITICAL_REPEAT=3
EOF
  title "Настройки сохранены: $DIR/config.sh" "Saved settings to $DIR/config.sh"
fi

# ---- build the menu bar app --------------------------------------------------
title "Собираю LeakWatch.app..." "Building LeakWatch.app..."
mkdir -p "$APP/Contents/MacOS"
swiftc -O -swift-version 5 -o "$APP/Contents/MacOS/LeakWatch" "$SRC/LeakWatch.swift"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>LeakWatch</string>
  <key>CFBundleIdentifier</key><string>com.leakwatch.app</string>
  <key>CFBundleExecutable</key><string>LeakWatch</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
</dict></plist>
EOF
codesign --force -s - "$APP" >/dev/null 2>&1 || true

# ---- launchd: hourly test + app at login --------------------------------------
if [ "${LEAKWATCH_NO_LAUNCH:-0}" != "1" ]; then
  cat > "$LA/com.leakwatch.test.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.leakwatch.test</string>
  <key>ProgramArguments</key><array><string>/bin/bash</string><string>$DIR/leakwatch.sh</string></array>
  <key>EnvironmentVariables</key><dict><key>PATH</key><string>/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin</string></dict>
  <key>StartInterval</key><integer>3600</integer>
  <key>RunAtLoad</key><true/>
  <key>AbandonProcessGroup</key><true/>
</dict></plist>
EOF
  cat > "$LA/com.leakwatch.app.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.leakwatch.app</string>
  <key>ProgramArguments</key><array><string>$APP/Contents/MacOS/LeakWatch</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>ProcessType</key><string>Interactive</string>
</dict></plist>
EOF
  for job in test app; do
    launchctl bootout "gui/$(id -u)/com.leakwatch.$job" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$LA/com.leakwatch.$job.plist"
  done
fi

title "Готово! LeakWatch работает." "Done! LeakWatch is running."
say "  • Строка меню: значок ✓/✗ DNS   • Виджет: справа вверху (можно перетащить)" \
    "  • Menu bar: ✓/✗ DNS icon         • Desktop widget: top-right (drag to move)"
say "  • Проверка при входе и каждый час; оповещения — только если что-то не так." \
    "  • Tests run at login and every hour; alerts only when something is wrong."
say "  • Настройки: $DIR/config.sh   • Журнал: $DIR/leakwatch.log" \
    "  • Settings: $DIR/config.sh    • Log: $DIR/leakwatch.log"
say "  • Удаление: ~/.leakwatch/uninstall.sh" "  • Uninstall: ~/.leakwatch/uninstall.sh"

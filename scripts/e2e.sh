#!/bin/zsh
# End-to-end tests on the live system: builds and installs Rasklad, opens a small test
# host app, presses real keys with Tests/Drive and checks the host's text.
# Report: build/e2e/report.md. Exit code is non-zero if any check fails.
#
# Takes over the keyboard and mouse for about a minute: don't touch them while it runs.
# Needs: Rasklad's Accessibility and Input Monitoring (as for normal use), Accessibility for
# the app that runs this script (Terminal, iTerm, Claude...) so the driver can post events,
# ABC (or US) and Russian layouts enabled.
# Restores afterwards: Rasklad settings (hotkey, exclusions, ...), the keyboard layout, the clipboard.
set -uo pipefail
cd "$(dirname "$0")/.."

OUT=$PWD/build/e2e
DRIVE=$OUT/drive
HOST_APP=$OUT/RaskladE2EHost.app
HOST_ID=local.rasklad.e2e-host
RASKLAD=~/Applications/Rasklad.app
LOG=$OUT/rasklad.log
REPORT=$OUT/report.md
ROWS=$OUT/rows.md

rm -rf "$OUT"; mkdir -p "$OUT"
: > "$ROWS"
FAILS=0; PASSES=0; SKIPS=0

# ---------- build ----------
echo "==> build"
./build.sh install >/dev/null || { echo "build failed"; exit 1; }
swiftc -swift-version 5 Tests/Drive/main.swift Sources/Layouts.swift \
  -framework Carbon -framework Cocoa -o "$DRIVE" || exit 1
mkdir -p "$HOST_APP/Contents/MacOS"
swiftc -swift-version 5 Tests/E2E/Host/main.swift -framework Cocoa \
  -o "$HOST_APP/Contents/MacOS/RaskladE2EHost" || exit 1
cat > "$HOST_APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>$HOST_ID</string>
  <key>CFBundleName</key><string>RaskladE2EHost</string>
  <key>CFBundleExecutable</key><string>RaskladE2EHost</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
EOF
codesign --force --sign - "$HOST_APP" 2>/dev/null

if ! "$DRIVE" check; then
  echo "The driver may not post key events. Give Accessibility to the app running this script"
  echo "(System Settings → Privacy & Security → Accessibility: Terminal, iTerm, ...), then run again."
  exit 1
fi

LAYOUTS=$("$DRIVE" layouts)
ABC=$(echo "$LAYOUTS" | grep -E '\.(ABC|US)$' | head -1)
RU=$(echo "$LAYOUTS" | grep -E '\.Russian' | head -1)
if [[ -z "$ABC" || -z "$RU" ]]; then echo "need ABC (or US) and Russian layouts enabled"; exit 1; fi

# ---------- save the user's state, restore it on exit ----------
ORIG_LAYOUT=$("$DRIVE" layout)
"$DRIVE" clip-save "$OUT/clipboard.plist"
HAD_PREFS=0
if defaults export local.rasklad "$OUT/prefs.plist" 2>/dev/null; then HAD_PREFS=1; fi

restore() {
  pkill -x RaskladE2EHost 2>/dev/null
  pkill -x Rasklad 2>/dev/null; sleep 0.5
  if (( HAD_PREFS )); then defaults import local.rasklad "$OUT/prefs.plist"
  else defaults delete local.rasklad 2>/dev/null; fi
  for _ in {1..10}; do open "$RASKLAD" 2>/dev/null; sleep 0.5; pgrep -x Rasklad >/dev/null && break; done
  "$DRIVE" clip-restore "$OUT/clipboard.plist"
  "$DRIVE" layout "$ORIG_LAYOUT" >/dev/null
  [[ -n "${LOG_PID:-}" ]] && kill "$LOG_PID" 2>/dev/null
}
trap restore EXIT
trap 'exit 130' INT TERM

/usr/bin/log stream --predicate 'subsystem == "local.rasklad"' --level debug --style compact > "$LOG" 2>&1 &
LOG_PID=$!
for _ in {1..50}; do grep -q "Filtering the log data" "$LOG" && break; sleep 0.1; done

# Starts Rasklad with clean settings plus the given `defaults write` arguments
# (each argument is one quoted string, e.g. "hotkey doubleOption").
launch_rasklad() {
  pkill -x Rasklad; while pgrep -x Rasklad >/dev/null; do sleep 0.1; done
  defaults delete local.rasklad 2>/dev/null
  local kv; for kv in "$@"; do eval defaults write local.rasklad $kv; done
  local before=$(grep -c "event tap: started" "$LOG") attempt
  for attempt in 1 2 3 4 5; do
    open "$RASKLAD" 2>/dev/null # may fail with -600 right after the previous instance quit: retry
    for _ in {1..30}; do
      (( $(grep -c "event tap: started" "$LOG") > before )) && { sleep 0.5; return 0; }
      sleep 0.1
    done
  done
  echo "Rasklad didn't start (no 'event tap: started' in the log)"; exit 1
}

# ---------- helpers ----------
text() { cat "$OUT/host/text.txt"; }
secure_text() { cat "$OUT/host/secure.txt"; }
click_host() { "$DRIVE" click $(cat "$OUT/host/click.txt"); sleep 0.3; }
wait_ui() { sleep "${1:-0.6}"; }

# Fresh scenario: ABC layout, empty text view focused, Rasklad's buffer cleared by a click.
prepare() {
  "$DRIVE" layout "$ABC" >/dev/null
  "$DRIVE" host focus-text
  "$DRIVE" host clear
  click_host
}

show() { local s=${1//$'\n'/⏎}; s=${s//|/\\|}; print -r -- "\`$s\`"; }
layout_name() { [[ $1 == "$RU" ]] && echo RU || { [[ $1 == "$ABC" ]] && echo EN || echo "$1"; } }

# check <scenario> <what was done> <expected> <actual>
check() {
  local result=PASS
  if [[ "$3" == "$4" ]]; then (( PASSES++ )); else result=FAIL; (( FAILS++ )); fi
  print -r -- "| $1 | $2 | $(show "$3") | $(show "$4") | **$result** |" >> "$ROWS"
  printf '%-4s %s: %s\n' "$result" "$1" "$2"
}

skip() {
  (( SKIPS++ ))
  print -r -- "| $1 | $2 | — | — | SKIP |" >> "$ROWS"
  echo "SKIP $1: $2"
}

log_mark() { wc -l < "$LOG" | tr -d ' '; }
log_since() { tail -n +$(( $1 + 1 )) "$LOG"; }

# ---------- start ----------
echo "==> e2e: don't touch the keyboard and mouse until it finishes (~1 min)"
mkdir -p "$OUT/host"
launch_rasklad
open -n "$HOST_APP" --args "$OUT/host"
for _ in {1..50}; do [[ -f "$OUT/host/ready" ]] && break; sleep 0.1; done
[[ -f "$OUT/host/ready" ]] || { echo "test host didn't start"; exit 1; }
sleep 0.5

scenario_basic() {
  # 1. Basic conversion and back.
  prepare
  mark=$(log_mark)
  "$DRIVE" type "ghbdtn vbh rfr ltkf"; wait_ui 0.3
  "$DRIVE" shift2; wait_ui
  check "Конвертация" "\`ghbdtn vbh rfr ltkf\` + двойной Shift" "привет мир как дела" "$(text)"
  check "Конвертация" "раскладка после конвертации" "RU" "$(layout_name "$("$DRIVE" layout)")"
  "$DRIVE" shift2; wait_ui
  check "Конвертация" "повторный двойной Shift возвращает" "ghbdtn vbh rfr ltkf" "$(text)"
  check "Конвертация" "раскладка после возврата" "EN" "$(layout_name "$("$DRIVE" layout)")"

  # Feedback: both conversions above should have played the sound and shown the hint.
  feedback=$(log_since $mark)
  check "Feedback" "звук при конвертации (лог \`feedback: sound played=true\`)" "2" \
    "$(echo "$feedback" | grep -c 'feedback: sound played=true')"
  check "Feedback" "подсказка EN → RU, затем RU → EN (лог \`feedback: hint\`)" "EN → RU;RU → EN" \
    "$(echo "$feedback" | grep -o 'feedback: hint .*' | sed 's/feedback: hint //' | paste -sd ';' -)"
}

scenario_continue() {
  # 2. Typing on after a conversion converts only the new text.
  prepare
  "$DRIVE" type "ghbdtn"; wait_ui 0.3
  "$DRIVE" shift2; wait_ui
  "$DRIVE" type " vbh"; wait_ui 0.3   # layout is Russian now: these keys type " мир"
  "$DRIVE" shift2; wait_ui
  check "Допечатка" "\`ghbdtn\` + Shift×2, допечатать \`vbh\` (в RU → \` мир\`) + Shift×2" "привет vbh" "$(text)"
}

scenario_resets() {
  # 3. Resets: only what was typed after them is converted.
  prepare
  "$DRIVE" type "ghbdtn"; "$DRIVE" key 36; "$DRIVE" type "vbh"; wait_ui 0.3
  "$DRIVE" shift2; wait_ui
  check "Сброс: Enter" "\`ghbdtn\` ⏎ \`vbh\` + Shift×2" $'ghbdtn\nмир' "$(text)"

  prepare
  "$DRIVE" type "ghbdtn"; wait_ui 0.2; click_host; "$DRIVE" type " vbh"; wait_ui 0.3
  "$DRIVE" shift2; wait_ui
  check "Сброс: клик" "\`ghbdtn\`, клик, \` vbh\` + Shift×2" "ghbdtn мир" "$(text)"

  prepare
  "$DRIVE" type "ghbdtn"; "$DRIVE" key 123; "$DRIVE" key 124; "$DRIVE" type " vbh"; wait_ui 0.3
  "$DRIVE" shift2; wait_ui
  check "Сброс: стрелки" "\`ghbdtn\`, ←, →, \` vbh\` + Shift×2" "ghbdtn мир" "$(text)"

  prepare
  "$DRIVE" type "ghbdtn"; wait_ui 0.2
  "$DRIVE" layout "$RU" >/dev/null; "$DRIVE" layout "$ABC" >/dev/null
  "$DRIVE" type " vbh"; wait_ui 0.3
  "$DRIVE" shift2; wait_ui
  check "Сброс: смена раскладки" "\`ghbdtn\`, вручную RU и обратно EN, \` vbh\` + Shift×2" "ghbdtn мир" "$(text)"
}

scenario_selection() {
  # 4. Selection: converted through the clipboard, which is restored afterwards.
  prepare
  "$DRIVE" type "ghbdtn vbh"; wait_ui 0.3
  "$DRIVE" clip-set "e2e-clipboard-sentinel"
  "$DRIVE" select-word; wait_ui 0.3
  "$DRIVE" shift2; wait_ui 1.5
  check "Выделение" "\`ghbdtn vbh\`, Option+Shift+← (выделить \`vbh\`) + Shift×2" "ghbdtn мир" "$(text)"
  check "Выделение" "буфер обмена восстановлен" "e2e-clipboard-sentinel" "$("$DRIVE" clip-get)"
  check "Выделение" "раскладка после конвертации выделения" "RU" "$(layout_name "$("$DRIVE" layout)")"
}

# Another app may own double Option (e.g. the ChatGPT launcher): after the tap, keys go to its
# window instead of ours. Probe it: tap double Option (not Rasklad's hotkey now), type, look.
option_is_free() {
  prepare
  "$DRIVE" tap doubleOption; wait_ui
  "$DRIVE" type "q"; wait_ui 0.3
  local got=$(text)
  "$DRIVE" key 53; click_host # close whatever opened and take the focus back
  [[ "$got" == "q" ]]
}

scenario_hotkeys() {
  # 5. Hotkeys from the menu: the chosen one fires, the others don't.
  launch_rasklad
  local option_free=1
  option_is_free || option_free=0
  for hk in doubleOption doubleControl doubleCommand rightOption; do
    if [[ $hk == doubleOption ]] && (( ! option_free )); then
      skip "Хоткей $hk" "двойной Option перехватывает другое приложение$(pgrep -fl bare-modifier-monitor >/dev/null && echo ' (запущен bare-modifier-monitor из ChatGPT.app)'): нажатия после него не доходят до окна"
      continue
    fi
    launch_rasklad "hotkey $hk"
    prepare
    "$DRIVE" type "ghbdtn"; wait_ui 0.3
    "$DRIVE" shift2; wait_ui
    check "Хоткей $hk" "\`ghbdtn\` + двойной Shift (не выбран)" "ghbdtn" "$(text)"
    "$DRIVE" tap $hk; wait_ui
    check "Хоткей $hk" "затем $hk" "привет" "$(text)"
    "$DRIVE" tap $hk; wait_ui
    check "Хоткей $hk" "повторный $hk возвращает" "ghbdtn" "$(text)"
  done
  launch_rasklad "hotkey doubleShift"
  prepare
  "$DRIVE" type "ghbdtn"; wait_ui 0.3
  "$DRIVE" tap doubleControl; wait_ui
  check "Хоткей doubleShift" "\`ghbdtn\` + двойной Control (не выбран)" "ghbdtn" "$(text)"
  "$DRIVE" shift2; wait_ui
  check "Хоткей doubleShift" "затем двойной Shift" "привет" "$(text)"
}

scenario_case() {
  # 6. Case inversion on its own hotkey (double Command by default); layout is not switched.
  launch_rasklad
  prepare
  "$DRIVE" type "ghbdtn"; wait_ui 0.3
  "$DRIVE" tap doubleCommand; wait_ui
  check "Регистр" "\`ghbdtn\` + двойной Command" "GHBDTN" "$(text)"
  check "Регистр" "раскладка не переключилась" "EN" "$(layout_name "$("$DRIVE" layout)")"
  "$DRIVE" tap doubleCommand; wait_ui
  check "Регистр" "повторный двойной Command возвращает" "ghbdtn" "$(text)"

  prepare
  "$DRIVE" type "Ghbdtn"; wait_ui 0.3
  "$DRIVE" tap doubleCommand; wait_ui
  check "Регистр" "\`Ghbdtn\` + двойной Command" "gHBDTN" "$(text)"
  "$DRIVE" shift2; wait_ui
  check "Регистр" "затем двойной Shift (раскладка)" "пРИВЕТ" "$(text)"

  prepare
  "$DRIVE" clip-set "e2e-clipboard-sentinel"
  "$DRIVE" type "hello world"; wait_ui 0.3
  "$DRIVE" select-word; wait_ui 0.3
  "$DRIVE" tap doubleCommand; wait_ui 1.5
  check "Регистр" "выделение \`world\` + двойной Command" "hello WORLD" "$(text)"
  check "Регистр" "буфер обмена восстановлен" "e2e-clipboard-sentinel" "$("$DRIVE" clip-get)"

  launch_rasklad "caseHotkey off"
  prepare
  "$DRIVE" type "ghbdtn"; wait_ui 0.3
  "$DRIVE" tap doubleCommand; wait_ui
  check "Регистр" "выключен: \`ghbdtn\` + двойной Command" "ghbdtn" "$(text)"
  launch_rasklad
}

scenario_exclusions() {
  # 6. Exclusions: nothing happens in an excluded app.
  launch_rasklad "excludedApps -array com.apple.Terminal $HOST_ID"
  sleep 1 # Rasklad looks at the frontmost app once more 1 s after launch
  prepare
  "$DRIVE" type "ghbdtn"; wait_ui 0.3
  "$DRIVE" shift2; wait_ui
  check "Исключения" "хост в исключениях: \`ghbdtn\` + Shift×2" "ghbdtn" "$(text)"
  check "Исключения" "раскладка не изменилась" "EN" "$(layout_name "$("$DRIVE" layout)")"
  launch_rasklad
}

scenario_secure() {
  # 7. Secure input: a password field turns on Secure Event Input; Rasklad must do nothing.
  prepare
  "$DRIVE" host focus-secure; wait_ui 0.3
  mark=$(log_mark)
  "$DRIVE" type "ghbdtn"; wait_ui 0.3
  "$DRIVE" shift2; wait_ui
  check "Пароль" "поле пароля: \`ghbdtn\` + Shift×2" "ghbdtn" "$(secure_text)"
  check "Пароль" "раскладка не изменилась" "EN" "$(layout_name "$("$DRIVE" layout)")"
  check "Пароль" "в лог не попали нажатия (\`key: buffered\`)" "0" "$(log_since $mark | grep -c 'key: buffered')"
  "$DRIVE" host focus-text
}

SCENARIOS=(basic continue resets selection hotkeys case exclusions secure)
(( $# )) && SCENARIOS=("$@")
for s in $SCENARIOS; do "scenario_$s"; done

# ---------- report ----------
sleep 0.5
TOTAL=$(( PASSES + FAILS ))
{
  echo "# Rasklad e2e report"
  echo
  echo "- Date: $(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo "- Commit: $(git rev-parse --short HEAD)$(git diff --quiet HEAD -- Sources || echo ' (+ uncommitted changes in Sources)')"
  echo "- macOS: $(sw_vers -productVersion), layouts: $ABC, $RU; layout before the run (restored after): $ORIG_LAYOUT"
  echo "- Result: **$( (( FAILS )) && echo FAIL || echo PASS)** — $PASSES/$TOTAL checks passed, $SKIPS skipped"
  echo
  echo "| Scenario | Done | Expected | Got | Result |"
  echo "| --- | --- | --- | --- | --- |"
  cat "$ROWS"
  echo
  echo "## Rasklad log during the run"
  echo
  echo "Subsystem \`local.rasklad\`, debug level (per-key \`key: buffered\` lines left out)."
  echo
  echo '```'
  grep -v 'key: buffered' "$LOG" | grep -v '^Filtering the log data'
  echo '```'
} > "$REPORT"
rm -f "$ROWS"

echo "==> $PASSES/$TOTAL passed, $SKIPS skipped. Report: $REPORT"
(( FAILS == 0 ))

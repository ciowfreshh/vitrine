#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p out/tests
EXTRA_SOURCES="tests/ui-v21/check.m tweak/Sources/App/SettingsPlacement.m" bash harness/lyrics/build.sh
device=$(xcrun simctl list devices available -j | python3 -c 'import sys,json; d=json.load(sys.stdin); print(next(x["udid"] for values in d["devices"].values() for x in values if x["name"].startswith("iPhone")))')
xcrun simctl boot "$device" || true
xcrun simctl bootstatus "$device" -b
xcrun simctl install "$device" harness/lyrics/build/new/LyricsHarness.app
for language in en vi; do
  log="out/tests/ui-v21-$language.log"
  xcrun simctl launch --console "$device" com.vojta.lyricsharness.new -song duet -v21 1 -at 25 -rate 0 -spotifyglass.interfaceLanguage "$language" >"$log" 2>&1 &
  runner=$!
  for attempt in $(seq 1 60); do
    if grep -Eq 'V21 UI COMPLETE|V21 FAIL' "$log"; then break; fi
    sleep 1
  done
  xcrun simctl io "$device" screenshot "out/tests/ui-v21-$language.png"
  xcrun simctl terminate "$device" com.vojta.lyricsharness.new || true
  wait "$runner" || true
  cat "$log"
  grep -Fq 'V21 UI COMPLETE' "$log"
  if grep -Fq 'V21 FAIL' "$log"; then exit 1; fi
done

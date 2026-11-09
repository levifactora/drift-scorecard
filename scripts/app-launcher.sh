#!/bin/zsh
# Asks for a picture and videos, runs the scorecard, then opens the report.
# DRIFT_TEST_REFERENCE and DRIFT_TEST_VIDEOS skip the dialogs when testing.
HERE="$(cd "$(dirname "$0")" && pwd)"
TOOL="$HERE/../Resources/drift-scorecard"

alert() { osascript -e 'on run argv' -e 'display alert "Drift Scorecard" message (item 1 of argv) as critical' -e 'end run' "$1" >/dev/null; }

if [[ -n "$DRIFT_TEST_REFERENCE" ]]; then
  REFERENCE="$DRIFT_TEST_REFERENCE"
  VIDEOS="$DRIFT_TEST_VIDEOS"
else
  REFERENCE="$(osascript -e 'POSIX path of (choose file with prompt "Choose your reference picture" of type {"public.image"})')" || exit 0
  CHOICE="$(osascript -e 'button returned of (display dialog "What do you want to check?" buttons {"Cancel", "One video", "A folder of videos"} default button 3)')" || exit 0
  if [[ "$CHOICE" == "One video" ]]; then
    VIDEOS="$(osascript -e 'POSIX path of (choose file with prompt "Choose your video" of type {"public.movie"})')" || exit 0
  else
    VIDEOS="$(osascript -e 'POSIX path of (choose folder with prompt "Choose the folder of videos")')" || exit 0
  fi
fi

OUT="$HOME/Documents/Drift Scorecard Reports/$(date +%Y-%m-%d-%H%M%S)"
[[ -n "$DRIFT_TEST_OUT" ]] && OUT="$DRIFT_TEST_OUT"
ERRORS="$(mktemp)"
"$TOOL" "$REFERENCE" "$VIDEOS" --out "$OUT" >/dev/null 2>"$ERRORS"
CODE=$?
MESSAGE="$(cat "$ERRORS")"
rm -f "$ERRORS"
if [[ $CODE -ge 2 ]]; then
  if [[ -n "$DRIFT_TEST_REFERENCE" ]]; then print -r -- "$MESSAGE"; else alert "$MESSAGE"; fi
  exit 1
fi
[[ -n "$DRIFT_TEST_REFERENCE" ]] || open "$OUT/report.html"

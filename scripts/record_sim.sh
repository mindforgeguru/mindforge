#!/usr/bin/env bash
#
# record_sim.sh — record the booted iOS simulator to a video, for Instagram.
#
# Usage:
#   scripts/record_sim.sh              # records the currently booted sim
#   scripts/record_sim.sh my_name      # custom output name (default: timetable_demo)
#
# How to use tomorrow:
#   1. Boot the sim + run the app (see notes at bottom).
#   2. Run this script. It starts screen recording.
#   3. Tap through the app to the timetable.
#   4. Press Ctrl-C to stop.
#   5. It saves the raw recording AND an Instagram Reels (9:16, 1080x1920) version.
#
set -euo pipefail

NAME="${1:-timetable_demo}"
OUTDIR="$HOME/Desktop/mindforge_clips"
mkdir -p "$OUTDIR"

RAW="$OUTDIR/${NAME}_raw.mp4"
REEL="$OUTDIR/${NAME}_reel.mp4"

# Grab the booted simulator's UDID.
UDID="$(xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}' | head -1 || true)"
if [ -z "$UDID" ]; then
  echo "No booted simulator found. Boot one first, e.g.:"
  echo "  xcrun simctl boot 'iPhone 17 Pro' && open -a Simulator"
  exit 1
fi

echo "Recording booted sim ($UDID)..."
echo ">>> Tap through to the timetable now. Press Ctrl-C when done. <<<"

# recordVideo stops cleanly on SIGINT and finalizes the file.
xcrun simctl io "$UDID" recordVideo --codec=h264 "$RAW" || true

echo ""
echo "Raw recording saved: $RAW"

# Make an Instagram Reels-friendly 9:16 version: scale to fit width, pad to 1080x1920.
if command -v ffmpeg >/dev/null 2>&1; then
  echo "Building Instagram 9:16 version..."
  ffmpeg -y -i "$RAW" \
    -vf "scale=1080:-2:force_original_aspect_ratio=decrease,pad=1080:1920:(ow-iw)/2:(oh-ih)/2:color=0x16294A" \
    -c:v libx264 -pix_fmt yuv420p -movflags +faststart \
    "$REEL" >/dev/null 2>&1
  echo "Instagram version saved: $REEL"
else
  echo "ffmpeg not found — only the raw recording was saved."
fi

# ---------------------------------------------------------------------------
# Reminder: launching the app before recording
#
#   xcrun simctl boot 'iPhone 17 Pro' && open -a Simulator
#   cd frontend && flutter run -d 'iPhone 17 Pro'
#
# Wait for the home dashboard, then run this script in another terminal.
# ---------------------------------------------------------------------------

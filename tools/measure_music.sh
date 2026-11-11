#!/bin/bash
# Prints integrated loudness (EBU R128) for every song in assets/music so the
# LOUDNESS table in scripts/music.gd can be updated when songs are added.
# Requires ffmpeg. Never modifies the songs.
cd "$(dirname "$0")/../assets/music" || exit 1
for f in *.mp3 *.ogg; do
  [ -e "$f" ] || continue
  L=$(ffmpeg -nostats -i "$f" -af ebur128 -f null - 2>&1 | grep -E "^\s+I:" | tail -1 | awk '{print $2}')
  echo "	\"$f\": $L,"
done

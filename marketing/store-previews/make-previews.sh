#!/usr/bin/env bash
# App Store app previews (iPhone 6.9", 886x1920) from the demo-video takes' real-app footage.
# ffmpeg only; reruns overwrite the same files. See README.md.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
videos="$here/../videos"
min_seconds=16   # App Store wants 15-30 s; the last frame is held up to this
w=886 h=1920

# <n>-<name>  <video dir>  <member>  <de|en>-agnostic: same list for both locales
clips=("1-add-tick:add-tick:anna" "2-household-sync:household-sync:anna" "3-voice-add:voice-add:mia")
# locale dir : footage dir (each take hears a sentence in its own language)
locales=("de-DE:de" "en-US:en")

for loc in "${locales[@]}"; do
  dir="${loc%%:*}"; lang="${loc##*:}"
  out="$here/out/$dir/appstore-iphone69"
  mkdir -p "$out"
  for clip in "${clips[@]}"; do
    IFS=: read -r name video member <<<"$clip"
    src="$videos/$video/footage/$lang/$member.mkv"
    [[ -f "$src" ]] || { echo "missing footage: $src (run marketing/videos/remake.sh)" >&2; exit 1; }
    file="$out/$name.mp4"
    stale="$out/$name.BLOCKED.mp4"
    rm -f "$stale"
    src_s="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$src")"
    total="$(awk -v d="$src_s" -v m="$min_seconds" 'BEGIN{printf "%.3f", (d<m?m:d)}')"
    hold="$(awk -v d="$src_s" -v t="$total" 'BEGIN{printf "%.3f", t-d+0.1}')"
    tmp="$file.tmp.mp4"
    # cover width, crop the 1px the 9:19.5 window overshoots; never stretches
    ffmpeg -v error -y -i "$src" -f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=48000" \
      -filter_complex "[0:v]scale=-2:$h:flags=lanczos,crop=$w:$h,setsar=1,fps=30,tpad=stop_mode=clone:stop_duration=$hold,trim=duration=$total,setpts=PTS-STARTPTS,format=yuv420p[v]" \
      -map "[v]" -map 1:a -t "$total" \
      -c:v libx264 -profile:v high -level 4.1 -preset slow -crf 20 -r 30 -pix_fmt yuv420p \
      -c:a aac -b:a 128k -ar 48000 -ac 2 -movflags +faststart -f mp4 "$tmp"
    mv "$tmp" "$file"
    echo "wrote ${file#"$here"/}"
  done
done

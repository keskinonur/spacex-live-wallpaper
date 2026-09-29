#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="${1:-$ROOT/Media}"
BUILD="$ROOT/Build"
mkdir -p "$BUILD/ModuleCache"
FFMPEG="${FFMPEG:-$(command -v ffmpeg)}"
# Original JPEGs retain their colour and detail; only the camera crop moves.
# HEVC is encoded by Apple's VideoToolbox hardware encoder.
ENC=(-c:v hevc_videotoolbox -tag:v hvc1 -b:v 22M -maxrate 30M -pix_fmt yuv420p -color_primaries bt709 -color_trc bt709 -colorspace bt709 -movflags +faststart -an)
xcrun swiftc -O -module-cache-path "$BUILD/ModuleCache" "$ROOT/Sources/PhotoScene.swift" "$ROOT/Sources/PhotoRenderer.swift" -o "$BUILD/render-photo"
"$BUILD/render-photo" "$SOURCE/spacex_20260929_1.jpeg" "$BUILD/wide.mp4" wide
"$BUILD/render-photo" "$SOURCE/spacex_20260929_2.jpeg" "$BUILD/close.mp4" close
"$FFMPEG" -hide_banner -loglevel warning -y -i "$SOURCE/spacex_20260929.mp4" \
  -t 20 -vf 'fps=30,scale=3840:2160:flags=lanczos,setsar=1' \
  "${ENC[@]}" "$BUILD/launch.mp4"
# Add the first 2 seconds again, then remove them from the beginning.
# The last frame now meets the next first frame at the same camera position.
"$FFMPEG" -hide_banner -loglevel warning -y -filter_complex_threads 2 \
  -i "$BUILD/wide.mp4" -i "$BUILD/close.mp4" -i "$BUILD/launch.mp4" -t 2 -i "$BUILD/wide.mp4" \
  -filter_complex "[0:v]settb=AVTB,setpts=PTS-STARTPTS[a];[1:v]settb=AVTB,setpts=PTS-STARTPTS[b];[2:v]settb=AVTB,setpts=PTS-STARTPTS[c];[3:v]settb=AVTB,setpts=PTS-STARTPTS[d];[a][b]xfade=transition=fade:duration=2:offset=16[ab];[ab][c]xfade=transition=fade:duration=2:offset=32[abc];[abc][d]xfade=transition=fade:duration=2:offset=50,trim=start=2:end=52,setpts=PTS-STARTPTS,format=yuv420p[out]" \
  -map '[out]' -r 30 "${ENC[@]}" "$BUILD/SpaceX-4K-Loop-new.mp4"
mv "$BUILD/SpaceX-4K-Loop-new.mp4" "$ROOT/SpaceX-4K-Loop.mp4"
echo "Rendered: $ROOT/SpaceX-4K-Loop.mp4"

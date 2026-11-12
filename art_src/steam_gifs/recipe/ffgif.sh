#!/bin/bash
# ffgif.sh <frames dir> <out.gif> <first frame> <last frame> <w:h:x:y crop> <out width>
D="$1"; OUT="$2"; A="$3"; B="$4"; CROP="$5"; W="$6"
ffmpeg -y -loglevel error -framerate 30 -start_number "$A" -i "$D/frame%08d.png" -frames:v $((B-A+1)) \
  -vf "fps=${FPS:-30},crop=$CROP,scale=$W:-2:flags=lanczos,split[a][b];[a]palettegen=max_colors=${COLORS:-256}:stats_mode=diff[p];[b][p]paletteuse=dither=${DITHER:-none}:diff_mode=rectangle" \
  -loop 0 "$OUT" && python -c "import os,sys; print(sys.argv[1], round(os.path.getsize(sys.argv[1])/1e6,2),'MB')" "$OUT"

#!/usr/bin/env bash
# Draws the pinkline art with ImageMagick:  art/make-art.sh
#   notch.png  the little white tick that sits on a pink line
#   stone.png  a seamless grey stone tile for the desktop
set -e
cd "$(dirname "$0")"
# 5x2 tick, pointing up: ..#.. / .###.
convert -size 5x2 xc:none -fill white -draw 'point 2,0' -draw 'line 1,1 3,1' PNG32:notch.png
# blurred noise with tiled edges, so the tile repeats without seams
convert -size 256x256 xc: -seed 55 +noise Random -channel G -separate +channel \
    -virtual-pixel tile -blur 0x2 \( +clone -blur 0x12 \) -compose blend -define compose:args=35 -composite \
    -auto-level -level 0%,100% +level 30%,52% -colorspace gray -depth 8 stone.png

#!/bin/sh
# Turns full-size screenshots into the AVIF and WebP files in static/shots.
# Usage: sh scripts/images.sh [screenshot dir]. The dir holds the PNGs from
# `mielwm snapshot` and `mielwm --settings-preview` (settings/ inside it).
set -e
src=${1:-/tmp/site-shots}
out=$(dirname "$0")/../static/shots
icon=$(dirname "$0")/../../Resources/AppIcon.png
mkdir -p "$out"

# name, source file, widths
shot() {
	name=$1 file=$2
	shift 2
	for w in "$@"; do
		magick "$file" -strip -resize "${w}x>" "PNG24:/tmp/mielwm-shot.png"
		cwebp -quiet -q 80 -m 6 /tmp/mielwm-shot.png -o "$out/$name-$w.webp"
		avifenc -q 62 -s 4 /tmp/mielwm-shot.png "$out/$name-$w.avif" >/dev/null
	done
}

for theme in dark light; do
	shot overview-$theme "$src/overview-$theme.png" 2200 1200
	shot search-$theme "$src/search-$theme.png" 1600 900
	shot switcher-$theme "$src/switcher-$theme.png" 1600 900
	shot desktop-$theme "$src/desktop-$theme.png" 1600 900
	shot keyboard-$theme "$src/settings/settings-keyboard-states2-$theme.png" 1000
	shot import-$theme "$src/settings/import-$theme.png" 520
	# the menu bar sheet holds two copies side by side; keep the left one
	magick "$src/settings/menubar-$theme.png" -crop 350x256+0+0 +repage /tmp/mielwm-menubar.png
	shot menubar-$theme /tmp/mielwm-menubar.png 350
done

# the app icon, for the header, the favicon and the share card
magick "$icon" -resize 128x128 -strip "$out/../icon-128.png"
magick "$icon" -resize 64x64 -strip "$out/../favicon.png"
magick "$icon" -resize 180x180 -strip "$out/../apple-touch-icon.png"
# share card: the overview, cropped to 1200x630, the icon in a corner
magick "$src/overview-dark.png" -resize 1200x630^ -gravity center -extent 1200x630 \
	\( "$icon" -resize 120x120 \) -gravity southwest -geometry +48+48 -composite \
	-strip -quality 85 "$out/../og.jpg"
rm -f /tmp/mielwm-shot.png /tmp/mielwm-menubar.png

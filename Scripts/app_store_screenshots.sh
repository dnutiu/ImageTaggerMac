#!/bin/bash
#
# Renders the App Store screenshots in AppStore/Screenshots from the frames in AppStore/screenshots.html, with Google
# Chrome. Each frame combines a screenshot of the app with a headline, and is saved as <frame ID>.jpg, because App Store
# Connect doesn't accept images with an alpha channel.
#
# Usage:
#   Scripts/app_store_screenshots.sh
#
# The frames are 1440×900, an App Store size for Mac apps. Set SCALE=2 to render them at 2880×1800, once the app
# screenshots they use are large enough.

set -euo pipefail

cd "$(dirname "$0")/.."

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
PAGE="$PWD/AppStore/screenshots.html"
OUTPUT=AppStore/Screenshots
SCALE=${SCALE:-1}

fail() {
    echo "error: $*" >&2
    exit 1
}

[[ -x "$CHROME" ]] || fail "Google Chrome wasn't found in /Applications"

TEMPORARY=$(mktemp -d)
trap 'rm -rf "$TEMPORARY"' EXIT
mkdir -p "$OUTPUT"

for frame in $(grep -o 'class="frame[^"]*" id="[^"]*"' "$PAGE" | sed 's/.*id="//; s/"$//'); do
    "$CHROME" --headless=new --disable-gpu --hide-scrollbars --virtual-time-budget=3000 --window-size=1440,900 \
        --force-device-scale-factor="$SCALE" --screenshot="$TEMPORARY/$frame.png" "file://$PAGE#$frame" 2> /dev/null
    sips -s format jpeg -s formatOptions 92 "$TEMPORARY/$frame.png" --out "$OUTPUT/$frame.jpg" > /dev/null
    echo "==> $OUTPUT/$frame.jpg"
done

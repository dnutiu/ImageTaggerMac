#!/bin/bash
#
# Builds a notarized DMG of ImageTagger, and optionally publishes it as a GitHub release.
#
# The app is signed with the team's Developer ID certificate and notarized with the Apple Account that's signed in
# to Xcode (Xcode › Settings › Apple Accounts), so no notarization password is needed. Without an Xcode account, as on
# GitHub Actions, set APP_STORE_CONNECT_KEY_PATH, APP_STORE_CONNECT_KEY_ID and APP_STORE_CONNECT_ISSUER_ID to use an
# App Store Connect API key instead. Notarization usually takes a few minutes, but it can take much longer,
# especially for a team's first submissions.
#
# Usage:
#   Scripts/release.sh                          Archive, notarize, and create build/release/ImageTagger-<version>.dmg
#   Scripts/release.sh --app <ImageTagger.app>  Create the DMG from an app that's already notarized
#   Scripts/release.sh --publish <notes.md>     Also publish the DMG as the v<version> GitHub release
#
# Set NOTARIZATION_TIMEOUT_MINUTES to change how long to wait for notarization (180 minutes by default).

set -euo pipefail

cd "$(dirname "$0")/.."

OUTPUT=build/release
ARCHIVE="$OUTPUT/ImageTagger.xcarchive"
WEIGHTS=ImageTagger/Resources/TagPrediction.mlpackage/Data/com.apple.CoreML/weights/weight.bin
NOTARIZATION_TIMEOUT_MINUTES=${NOTARIZATION_TIMEOUT_MINUTES:-180}
APP=""
NOTES=""

fail() {
    echo "error: $*" >&2
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --app) APP="${2:?--app needs the path of the app}"; shift 2 ;;
        --publish) NOTES="${2:?--publish needs a release notes file}"; shift 2 ;;
        *) fail "unknown option $1" ;;
    esac
done

[[ -z "$NOTES" || -f "$NOTES" ]] || fail "release notes not found: $NOTES"
if [[ -n "$NOTES" ]]; then
    git fetch --quiet origin
    [[ -n "$(git branch --remotes --contains HEAD)" ]] || fail "push the current commit first, so the release can be tagged"
fi

# Authenticates xcodebuild with an App Store Connect API key, when one is set.
AUTHENTICATION=()
if [[ -n "${APP_STORE_CONNECT_KEY_PATH:-}" ]]; then
    AUTHENTICATION=(
        -authenticationKeyPath "$APP_STORE_CONNECT_KEY_PATH"
        -authenticationKeyID "${APP_STORE_CONNECT_KEY_ID:?set APP_STORE_CONNECT_KEY_ID}"
        -authenticationKeyIssuerID "${APP_STORE_CONNECT_ISSUER_ID:?set APP_STORE_CONNECT_ISSUER_ID}"
    )
fi

TEMPORARY=$(mktemp -d)
trap 'hdiutil detach "$TEMPORARY/mount" -quiet 2>/dev/null || true; rm -rf "$TEMPORARY"' EXIT
mkdir -p "$OUTPUT"

if [[ -z "$APP" ]]; then
    [[ -z "$(git status --porcelain)" ]] || fail "commit your changes first, so the release matches a commit"
    # Without Git LFS, the model's weights are a small pointer file and the app can't tag images.
    (( $(stat -f %z "$WEIGHTS") > 1000000 )) || fail "the model's weights are missing, run git lfs pull"

    echo "==> Archiving"
    rm -rf "$ARCHIVE" "$OUTPUT/notarized"
    # The archive is signed ad hoc, so no development certificate is needed. The export signs it with Developer ID.
    xcodebuild archive -project ImageTagger.xcodeproj -scheme ImageTagger -configuration Release \
        -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" \
        CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual -quiet

    echo "==> Signing with Developer ID and uploading for notarization"
    xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist Scripts/ExportOptions.plist \
        -exportPath "$TEMPORARY/upload" -allowProvisioningUpdates \
        ${AUTHENTICATION[@]+"${AUTHENTICATION[@]}"} -quiet

    echo "==> Waiting for notarization (up to $NOTARIZATION_TIMEOUT_MINUTES minutes)"
    deadline=$((SECONDS + NOTARIZATION_TIMEOUT_MINUTES * 60))
    until xcodebuild -exportNotarizedApp -archivePath "$ARCHIVE" -exportPath "$OUTPUT/notarized" \
        ${AUTHENTICATION[@]+"${AUTHENTICATION[@]}"} > "$OUTPUT/notarization.log" 2>&1; do
        if ! grep -q "is processing" "$OUTPUT/notarization.log"; then
            cat "$OUTPUT/notarization.log" >&2
            fail "notarization failed, see Xcode › Window › Organizer for details"
        fi
        if (( SECONDS > deadline )); then
            fail "the app is still being notarized. When it's done, run:
  xcodebuild -exportNotarizedApp -archivePath $ARCHIVE -exportPath $OUTPUT/notarized
  $0 --app $OUTPUT/notarized/ImageTagger.app"
        fi
        sleep 60
    done
    APP="$OUTPUT/notarized/ImageTagger.app"
fi

echo "==> Checking the app"
[[ -d "$APP" ]] || fail "app not found: $APP"
xcrun stapler validate -q "$APP" || fail "the app doesn't have a notarization ticket"
spctl --assess --type execute "$APP" || fail "Gatekeeper rejects the app"
syspolicy_check distribution "$APP"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="$OUTPUT/ImageTagger-$VERSION.dmg"

echo "==> Creating $DMG"
mkdir "$TEMPORARY/dmg"
ditto "$APP" "$TEMPORARY/dmg/ImageTagger.app"
ln -s /Applications "$TEMPORARY/dmg/Applications"
# hdiutil underestimates the size the app needs, so give the image enough room.
size=$(( $(du -sm "$TEMPORARY/dmg/ImageTagger.app" | cut -f1) + 50 ))
hdiutil create -volname ImageTagger -srcfolder "$TEMPORARY/dmg" -size "${size}m" -format UDZO -ov "$DMG" -quiet
hdiutil verify "$DMG" -quiet

echo "==> Checking the DMG as a download from the internet"
cp "$DMG" "$TEMPORARY/download.dmg"
xattr -w com.apple.quarantine "0081;$(printf %x "$(date +%s)");Safari;$(uuidgen)" "$TEMPORARY/download.dmg"
mkdir "$TEMPORARY/mount"
hdiutil attach "$TEMPORARY/download.dmg" -nobrowse -readonly -mountpoint "$TEMPORARY/mount" -quiet
ditto "$TEMPORARY/mount/ImageTagger.app" "$TEMPORARY/installed/ImageTagger.app"
hdiutil detach "$TEMPORARY/mount" -quiet
xattr -p com.apple.quarantine "$TEMPORARY/installed/ImageTagger.app" > /dev/null \
    || fail "the copied app should be quarantined like a download"
spctl --assess --type execute "$TEMPORARY/installed/ImageTagger.app" \
    || fail "Gatekeeper rejects the app installed from the DMG"

CHECKSUM=$(shasum -a 256 "$DMG" | cut -d ' ' -f 1)
echo "==> Created $DMG"
echo "    SHA-256: $CHECKSUM"

if [[ -n "$NOTES" ]]; then
    echo "==> Publishing the v$VERSION GitHub release"
    { cat "$NOTES"; printf '\n**SHA-256:** `%s`\n' "$CHECKSUM"; } > "$TEMPORARY/notes.md"
    gh release create "v$VERSION" "$DMG" --target "$(git rev-parse HEAD)" \
        --title "ImageTagger $VERSION" --notes-file "$TEMPORARY/notes.md"
fi

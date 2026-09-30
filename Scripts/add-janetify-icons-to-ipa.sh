#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./Scripts/add-janetify-icons-to-ipa.sh /path/to/Spotify.ipa

This script patches a decrypted Spotify IPA so the repo's janetify alternate icon
is included in the app bundle and registered in Info.plist for the app icon picker.

Requirements:
  - unzip
  - zip
  - plutil
  - bash

Notes:
  - Works on a decrypted Spotify IPA only.
  - The app must be re-signed after patching.
EOF
}

if [[ $# -ne 1 ]]; then
  usage
  exit 1
fi

IPA_PATH="$1"
if [[ ! -f "$IPA_PATH" ]]; then
  echo "IPA not found: $IPA_PATH" >&2
  exit 1
fi

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ICON_DIR="$REPO_DIR/Assets/AppIcon"

for f in \
  "$ICON_DIR/janetify@2x.png" \
  "$ICON_DIR/janetify@2x~ipad.png" \
  "$ICON_DIR/janetify@3x.png" \
  "$ICON_DIR/janetify~ipad.png"; do
  if [[ ! -f "$f" ]]; then
    echo "Missing required icon asset: $f" >&2
    exit 1
  fi
done

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

UNZIP_DIR="$TMPDIR/unzip"
mkdir -p "$UNZIP_DIR"
unzip -q "$IPA_PATH" -d "$UNZIP_DIR"

APP_DIR="$(find "$UNZIP_DIR/Payload" -maxdepth 2 -type d -name '*.app' | head -n 1)"
if [[ -z "$APP_DIR" ]]; then
  echo "Could not find an .app bundle inside the IPA." >&2
  exit 1
fi

for f in \
  "$ICON_DIR/janetify@2x.png" \
  "$ICON_DIR/janetify@2x~ipad.png" \
  "$ICON_DIR/janetify@3x.png" \
  "$ICON_DIR/janetify~ipad.png"; do
  cp "$f" "$APP_DIR/"
done

INFO_PLIST="$APP_DIR/Info.plist"
if [[ ! -f "$INFO_PLIST" ]]; then
  echo "Info.plist not found at $INFO_PLIST" >&2
  exit 1
fi

# Ensure the plist has CFBundleIcons / CFBundleAlternateIcons, creating them if needed.
if ! plutil -extract CFBundleIcons "raw" "$INFO_PLIST" >/dev/null 2>&1; then
  plutil -insert CFBundleIcons -dict "$INFO_PLIST"
fi

# Ensure CFBundlePrimaryIcon exists.
if ! plutil -extract CFBundleIcons.CFBundlePrimaryIcon "raw" "$INFO_PLIST" >/dev/null 2>&1; then
  plutil -insert CFBundleIcons.CFBundlePrimaryIcon -dict "$INFO_PLIST"
fi

# Ensure there is at least one icon file for the primary icon.
if ! plutil -extract CFBundleIcons.CFBundlePrimaryIcon.CFBundleIconFiles "raw" "$INFO_PLIST" >/dev/null 2>&1; then
  plutil -insert CFBundleIcons.CFBundlePrimaryIcon.CFBundleIconFiles -xml '<array><string>AppIcon60x60</string></array>' "$INFO_PLIST"
fi

# Ensure the alternate icon dictionary exists.
if ! plutil -extract CFBundleIcons.CFBundleAlternateIcons "raw" "$INFO_PLIST" >/dev/null 2>&1; then
  plutil -insert CFBundleIcons.CFBundleAlternateIcons -dict "$INFO_PLIST"
fi

# Register janetify as an alternate icon.
plutil -replace CFBundleIcons.CFBundleAlternateIcons.janetify -dict "$INFO_PLIST"
plutil -replace CFBundleIcons.CFBundleAlternateIcons.janetify.CFBundleIconFiles -xml '<array><string>janetify</string></array>' "$INFO_PLIST"

# Patch the app bundle back into the IPA.
OUT_IPA="${IPA_PATH%.ipa}-janetify.ipa"
rm -f "$OUT_IPA"
(cd "$UNZIP_DIR" && zip -qry "$OUT_IPA" Payload)

echo
echo "Patched IPA created: $OUT_IPA"
echo "Re-sign the IPA before installing."
echo "You can now use the app icon picker and select 'janetify'."

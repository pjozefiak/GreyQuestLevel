#!/usr/bin/env bash
# Build a distributable zip, and optionally sync it into a live WoW install.
#
#   ./scripts/package.sh            -> dist/<AddonName>-<version>.zip
#   ./scripts/package.sh --deploy   -> also copies the addon to /wow-addons
#
# /wow-addons is the bind mount configured in .devcontainer/devcontainer.json.
set -euo pipefail
cd "$(dirname "$0")/.."

ADDON_NAME="$(basename "$PWD")"
TOC="$ADDON_NAME.toc"
[ -f "$TOC" ] || { echo "no $TOC in $PWD"; exit 1; }

VERSION="$(sed -n 's/^## Version: *//p' "$TOC" | tr -d '\r')"
VERSION="${VERSION:-dev}"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
DEST="$STAGE/$ADDON_NAME"
mkdir -p "$DEST"

# Ship source only: no VCS, tooling, or build output.
rsync -a \
  --exclude '.git' \
  --exclude '.github' \
  --exclude '.devcontainer' \
  --exclude '.vscode' \
  --exclude 'dist' \
  --exclude 'scripts' \
  --exclude '.luacheckrc' \
  --exclude '.luarc.json' \
  --exclude 'stylua.toml' \
  --exclude '.editorconfig' \
  ./ "$DEST/"

mkdir -p dist
ZIP="$PWD/dist/$ADDON_NAME-$VERSION.zip"
rm -f "$ZIP"
(cd "$STAGE" && zip -qr "$ZIP" "$ADDON_NAME")
echo "built $ZIP"

if [ "${1:-}" = "--deploy" ]; then
  [ -d /wow-addons ] || { echo "/wow-addons is not mounted — see .devcontainer/README.md"; exit 1; }
  rm -rf "/wow-addons/$ADDON_NAME"
  cp -r "$DEST" "/wow-addons/$ADDON_NAME"
  echo "deployed to /wow-addons/$ADDON_NAME — run /reload in game"
fi

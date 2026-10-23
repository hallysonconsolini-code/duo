#!/bin/zsh
# Gera build/Duo.dmg com o Duo.app e um atalho para /Applications (arrastar para instalar).
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

cp -R build/Duo.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"

DMG="build/Duo-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "Duo $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
echo "Pronto: $PWD/$DMG"

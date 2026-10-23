#!/bin/zsh
# Publica uma versão nova: sobe o número, gera o DMG, faz commit + tag + push
# e cria a release no GitHub. O botão "Procurar atualizações" do app encontra a release.
#
# uso: scripts/release.sh 0.3.0 "o que mudou"
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=${1:?uso: scripts/release.sh <versão> "<notas>"}
NOTES=${2:-"Duo $VERSION"}
PLIST=Resources/Info.plist

if git rev-parse "v$VERSION" >/dev/null 2>&1; then
    echo "A tag v$VERSION já existe." >&2
    exit 1
fi

BUILD=$(( $(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$PLIST") + 1 ))
/usr/libexec/PlistBuddy -c "Set CFBundleShortVersionString $VERSION" -c "Set CFBundleVersion $BUILD" "$PLIST"

./scripts/make-dmg.sh

git add -A
git commit -q -m "Duo $VERSION" -m "$NOTES"
git tag -a "v$VERSION" -m "Duo $VERSION"
git push -q origin HEAD "v$VERSION"
gh release create "v$VERSION" "build/Duo-$VERSION.dmg" --title "Duo $VERSION" --notes "$NOTES"

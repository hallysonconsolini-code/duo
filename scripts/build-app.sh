#!/bin/zsh
# Compila o Duo e monta build/Duo.app. Assina com a identidade local "Duo Local Signing"
# (crie uma vez com scripts/setup-signing.sh) para o macOS lembrar as permissões entre
# instalações; sem ela, assina ad-hoc.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Duo"

APP=build/Duo.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Duo"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[[ -f Resources/AppIcon.icns ]] || swift scripts/make-icon.swift Resources/AppIcon.icns
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
IDENTITY=${DUO_SIGN_IDENTITY:-"Duo Local Signing"}
if security find-identity -p codesigning | grep -qF "\"$IDENTITY\""; then
    # Requisito do app = identificador + este certificado: igual em todo build.
    codesign --force --sign "$IDENTITY" --identifier local.duo.claude "$APP"
else
    echo "Aviso: identidade “$IDENTITY” não encontrada; assinando ad-hoc." >&2
    echo "       O macOS vai pedir as permissões de novo a cada instalação." >&2
    echo "       Para resolver, rode uma vez: scripts/setup-signing.sh" >&2
    codesign --force --sign - "$APP"
fi
echo "Pronto: $PWD/$APP"

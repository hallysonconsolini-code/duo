#!/bin/zsh
# Compila e instala o Duo em /Applications, substituindo a versão atual.
# Fecha o Duo antes (pede confirmação se houver painéis rodando) e abre de novo no fim.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh

if pgrep -x Duo >/dev/null; then
    echo "Fechando o Duo…"
    osascript -e 'quit app "Duo"' || true
    for _ in {1..120}; do
        pgrep -x Duo >/dev/null || break
        sleep 0.5
    done
    if pgrep -x Duo >/dev/null; then
        echo "O Duo continua aberto (cancelou ao fechar?). Instalação interrompida." >&2
        exit 1
    fi
fi

ditto build/Duo.app /Applications/Duo.app.new
rm -rf /Applications/Duo.app
mv /Applications/Duo.app.new /Applications/Duo.app
echo "Instalado: /Applications/Duo.app"
open /Applications/Duo.app

#!/bin/zsh
# Cria, uma vez só, um certificado local de assinatura de código ("Duo Local Signing")
# no keychain de login. Com ele, o build-app.sh assina o Duo sempre com a mesma
# identidade, e o macOS para de pedir de novo as permissões (discos, pastas,
# notificações...) a cada instalação. Assinado ad-hoc, cada build parecia um app novo.
#
# uso: scripts/setup-signing.sh
set -euo pipefail

NAME=${DUO_SIGN_IDENTITY:-"Duo Local Signing"}
KEYCHAIN=${DUO_KEYCHAIN:-"$HOME/Library/Keychains/login.keychain-db"}
OPENSSL=/usr/bin/openssl   # o do sistema (LibreSSL) gera um .p12 que o `security` importa sem ajustes

if security find-identity -p codesigning "$KEYCHAIN" | grep -qF "\"$NAME\""; then
    echo "A identidade “$NAME” já existe no keychain. Nada a fazer."
    exit 0
fi
if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "Existe um certificado “$NAME” sem a chave privada. Apague-o no Acesso às Chaves e rode de novo." >&2
    exit 1
fi

cat <<MSG
Vou criar o certificado “$NAME” (válido por 20 anos, só para assinar o Duo neste Mac)
e guardá-lo no keychain de login.

No fim vou pedir a senha de login do Mac (a do keychain), digitada aqui no Terminal.
Ela serve para liberar a chave só para o codesign, sem diálogo a cada build. Ela não é
gravada em lugar nenhum. Se preferir não digitar, aperte Enter: no primeiro build o
macOS vai perguntar “codesign quer usar a chave…”, e aí é só clicar em “Sempre Permitir”.

MSG

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<CNF
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no
[ dn ]
CN = $NAME
[ ext ]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
CNF

"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 7300 -config "$TMP/cert.cnf" \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
P12_PASS=$("$OPENSSL" rand -hex 16)
"$OPENSSL" pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
    -out "$TMP/id.p12" -passout "pass:$P12_PASS"

# -T: o codesign pode usar a chave sem pedir permissão.
security import "$TMP/id.p12" -k "$KEYCHAIN" -P "$P12_PASS" -T /usr/bin/codesign >/dev/null
echo "Certificado importado."

printf "Senha de login do Mac (Enter para pular): "
read -rs KEYCHAIN_PASS || KEYCHAIN_PASS=""
echo
if [[ -n "$KEYCHAIN_PASS" ]]; then
    # Só a chave deste certificado (-l), não as outras do keychain.
    if security set-key-partition-list -S apple-tool:,apple:,codesign: -s -l "$NAME" \
        -k "$KEYCHAIN_PASS" "$KEYCHAIN" >/dev/null 2>&1; then
        echo "Chave liberada para o codesign."
    else
        echo "Não consegui liberar a chave (senha errada?). No primeiro build, clique em “Sempre Permitir”."
    fi
fi
unset KEYCHAIN_PASS

# Um certificado autoassinado não precisa ser marcado como confiável para o codesign
# assinar; o requisito do app fica preso a este certificado, que é o que importa.
echo
echo "Pronto. Agora o scripts/build-app.sh assina com “$NAME”."
echo "Na primeira instalação assinada assim, o macOS pede as permissões mais uma vez; depois, não pede mais."

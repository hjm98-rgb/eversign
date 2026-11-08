#!/usr/bin/env bash
# 构建时现场生成签名证书链，不复用任何第三方 p12
set -e
OUT="${1:-victim.p12}"
OUT="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"

openssl genrsa -out root.key 2048 2>/dev/null
openssl req -new -x509 -days 3650 -key root.key -out root.crt \
  -subj "/C=CN/O=EverSign/OU=EverSign/CN=EverSign Root CA" \
  -addext "1.2.840.113635.100.6.2.18=DER:0500" \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "keyUsage=critical,keyCertSign,cRLSign" 2>/dev/null

openssl genrsa -out inter.key 2048 2>/dev/null
openssl req -new -key inter.key -out inter.csr \
  -subj "/C=CN/O=EverSign/OU=EverSign/CN=EverSign Certification Authority" 2>/dev/null
printf 'basicConstraints=critical,CA:TRUE,pathlen:0\nkeyUsage=critical,keyCertSign,cRLSign\n1.2.840.113635.100.6.2.18=DER:0500\n' > inter.ext
openssl x509 -req -in inter.csr -CA root.crt -CAkey root.key -CAcreateserial \
  -days 3650 -out inter.crt -extfile inter.ext 2>/dev/null

openssl genrsa -out leaf.key 2048 2>/dev/null
openssl req -new -key leaf.key -out leaf.csr \
  -subj "/C=CN/O=EverSign/OU=EverSign/CN=EverSign iPhone OS Application Signing" 2>/dev/null
printf 'basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=codeSigning\n1.2.840.113635.100.6.1.3=DER:0500\n' > leaf.ext
openssl x509 -req -in leaf.csr -CA inter.crt -CAkey inter.key -CAcreateserial \
  -days 3650 -out leaf.crt -extfile leaf.ext 2>/dev/null

cat leaf.crt inter.crt root.crt > chain.pem
openssl pkcs12 -export -inkey leaf.key -in leaf.crt -certfile chain.pem \
  -keypbe NONE -certpbe NONE -macalg sha1 -passout pass: -out "$OUT"
echo "[cert] $OUT $(stat -c%s "$OUT") bytes"

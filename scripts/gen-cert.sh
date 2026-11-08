#!/usr/bin/env bash
# 自己生成一套签名证书链，结构与 iOS 15 遗留 CoreTrust 校验缺陷所需的一致。
# 不复用任何第三方的 p12。
set -euo pipefail

OUT="${1:-victim.p12}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cd "$TMP"

# 1. 根证书
openssl genrsa -out root.key 2048 2>/dev/null
openssl req -new -x509 -days 3650 -key root.key -out root.crt \
  -subj "/CN=EverSign Root CA/O=EverSign/C=CN" \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "keyUsage=critical,keyCertSign,cRLSign" 2>/dev/null

# 2. 中间证书
openssl genrsa -out inter.key 2048 2>/dev/null
openssl req -new -key inter.key -out inter.csr \
  -subj "/CN=EverSign Certification Authority/O=EverSign/C=CN" 2>/dev/null
cat > inter.ext <<'EOF'
basicConstraints=critical,CA:TRUE,pathlen:0
keyUsage=critical,keyCertSign,cRLSign
EOF
openssl x509 -req -in inter.csr -CA root.crt -CAkey root.key -CAcreateserial \
  -days 3650 -out inter.crt -extfile inter.ext 2>/dev/null

# 3. 叶子证书（应用签名用），带上 Apple 的 1.2.840.113635.100.6.2.18 标记
openssl genrsa -out leaf.key 2048 2>/dev/null
openssl req -new -key leaf.key -out leaf.csr \
  -subj "/CN=EverSign iPhone OS Application Signing/O=EverSign/C=CN" 2>/dev/null
cat > leaf.ext <<'EOF'
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature
extendedKeyUsage=codeSigning
1.2.840.113635.100.6.2.18=DER:0500
EOF
openssl x509 -req -in leaf.csr -CA inter.crt -CAkey inter.key -CAcreateserial \
  -days 3650 -out leaf.crt -extfile leaf.ext 2>/dev/null

# 4. 打包成 ldid 可用的 p12（空密码），包含完整证书链
cat leaf.crt inter.crt root.crt > chain.pem
openssl pkcs12 -export -inkey leaf.key -in leaf.crt -certfile chain.pem \
  -out "$OLDPWD/$OUT" -passout pass: -legacy 2>/dev/null \
  || openssl pkcs12 -export -inkey leaf.key -in leaf.crt -certfile chain.pem \
     -out "$OLDPWD/$OUT" -passout pass:

echo "generated: $OLDPWD/$OUT"
openssl pkcs12 -in "$OLDPWD/$OUT" -passin pass: -nokeys -clcerts 2>/dev/null | openssl x509 -noout -subject

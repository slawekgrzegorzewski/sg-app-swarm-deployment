#!/usr/bin/env bash
set -Eeuo pipefail

certificate_file="${1:-gateway.crt}"
private_key_file="${2:-gateway.key}"
ca_file="${3:-dv_ca.pem}"
output_file="${4:-gateway.p12}"
chain_file="$(mktemp ./gateway-cert-chain.XXXXXX.pem)"
trap 'rm -f -- "$chain_file"' EXIT

cat "$certificate_file" "$ca_file" > "$chain_file"
openssl pkcs12 -export \
  -in "$chain_file" \
  -inkey "$private_key_file" \
  -name gateway \
  -out "$output_file"

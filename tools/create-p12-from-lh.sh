#!/bin/bash
cat sgapplication.crt dv_ca.pem > cert-chain.txt
openssl pkcs12 -export -in cert-chain.txt -inkey sgapplication.key -name 1 -out sgapplication.p12

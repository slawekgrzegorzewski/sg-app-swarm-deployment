#/bin/bash
openssl req -x509 -nodes -new -sha256 -days 1024 -newkey rsa:2048 -keyout RootCA.key -out RootCA.pem -subj "/C=US/CN=Example-Root-CA"
openssl x509 -outform pem -in RootCA.pem -out RootCA.crt

echo authorityKeyIdentifier=keyid,issuer > domains.ext
echo basicConstraints=CA:FALSE >> domains.ext
echo keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment >> domains.ext
echo subjectAltName = @alt_names >> domains.ext
echo [alt_names] >> domains.ext
echo DNS.1 = localhost >> domains.ext
echo DNS.2 = localhost.org >> domains.ext

openssl req -new -nodes -newkey rsa:2048 -keyout localhost.key -out localhost.csr -subj "/C=US/ST=YourState/L=YourCity/O=Example-Certificates/CN=localhost.local"
openssl x509 -req -sha256 -days 1024 -in localhost.csr -CA RootCA.pem -CAkey RootCA.key -CAcreateserial -extfile domains.ext -out localhost.crt

rm domains.ext
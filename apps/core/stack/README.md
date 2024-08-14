Docker registry API https://docker-docs.uclv.cu/registry/spec/api/

```bash
curl -X GET --basic -u <<user>>:<<password>> https://grzegorzewski.org:5000/v2/
```

```bash
curl -X GET --basic -u <<user>>:<<password> https://grzegorzewski.org:5000/v2/backend/tags/list
```

```bash
curl -X GET --basic -u  <<user>>:<<password> --header "Accept: application/vnd.oci.image.index.v1+json" https://grzegorzewski.org:5000/v2/backend/manifests/2024-07-16_18-53-2852e20-rpi4
```

```bash
curl -X DELETE --basic -u <<user>>:<<password> --header "Accept: application/vnd.docker.distribution.manifest.v2+json" --location https://grzegorzewski.org:5000/v2/backend/manifests/sha256:43ddb941870e3b035730a2f6a5f3a9ef44a294fd3607614bc490628459d6c960
```

```bash
curl -X GET --basic -u  <<user>>:<<password> --header "Accept: application/vnd.oci.image.index.v1+json" https://grzegorzewski.org:5000/v2/backend/blobs/sha256:43ddb941870e3b035730a2f6a5f3a9ef44a294fd3607614bc490628459d6c960
```
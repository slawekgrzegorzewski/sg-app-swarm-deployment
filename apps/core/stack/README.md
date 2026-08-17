Zot exposes the Docker Registry v2-compatible API through the Nginx reverse
proxy. The public endpoint is:

```text
https://grzegorzewski.pl:5005
```

The Zot service itself listens on port `5000` only inside the Swarm overlay
network. Authentication is handled by the Nginx Basic Auth layer.

The Zot web interface is available through the same reverse proxy:

```text
https://grzegorzewski.pl:5005/
```

Set the registry credentials before running the examples:

```bash
export REGISTRY_USER='user'
export REGISTRY_PASSWORD='password'
```

```bash
curl -X GET --basic -u "${REGISTRY_USER}:${REGISTRY_PASSWORD}" https://grzegorzewski.pl:5005/v2/
```

```bash
curl -X GET --basic -u "${REGISTRY_USER}:${REGISTRY_PASSWORD}" https://grzegorzewski.pl:5005/v2/backend/tags/list
```

```bash
curl -X GET --basic -u "${REGISTRY_USER}:${REGISTRY_PASSWORD}" --header "Accept: application/vnd.oci.image.index.v1+json" https://grzegorzewski.pl:5005/v2/backend/manifests/2024-07-16_18-53-2852e20
```

```bash
curl -X DELETE --basic -u "${REGISTRY_USER}:${REGISTRY_PASSWORD}" --header "Accept: application/vnd.docker.distribution.manifest.v2+json" --location https://grzegorzewski.pl:5005/v2/backend/manifests/sha256:43ddb941870e3b035730a2f6a5f3a9ef44a294fd3607614bc490628459d6c960
```

```bash
curl -X GET --basic -u "${REGISTRY_USER}:${REGISTRY_PASSWORD}" --header "Accept: application/vnd.oci.image.index.v1+json" https://grzegorzewski.pl:5005/v2/backend/blobs/sha256:43ddb941870e3b035730a2f6a5f3a9ef44a294fd3607614bc490628459d6c960
```

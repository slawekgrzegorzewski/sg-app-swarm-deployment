#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "$#" -ne 2 ]]; then
  echo "Usage: $(basename "$0") {frontend|backend|banks|tapo} IMAGE_TAG" >&2
  exit 2
fi

component="$1"
image_tag="$2"
if [[ ! "$image_tag" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]]; then
  echo 'Image tag may contain only letters, digits, underscores, dots, and hyphens.' >&2
  exit 2
fi

case "$component" in
  frontend) variable_name=FRONTEND_IMAGE_TAG ;;
  backend) variable_name=BACKEND_IMAGE_TAG ;;
  banks) variable_name=BANKS_IMAGE_TAG ;;
  tapo) variable_name=TAPO ;;
  *)
    echo "Unknown component: $component (expected frontend, backend, banks, or tapo)" >&2
    exit 2
    ;;
esac

cluster_root="${CLUSTER_ROOT:-/srv/cluster}"
environment_file="$cluster_root/image-tags.env"
lock_file="$cluster_root/.image-tags.lock"

if [[ ! -d "$cluster_root" ]]; then
  echo "Cluster root does not exist: $cluster_root" >&2
  exit 1
fi

if command -v flock >/dev/null 2>&1; then
  exec 9>"$lock_file"
  flock -x 9
fi

frontend_tag=latest
backend_tag=latest
banks_tag=latest
tapo_tag=latest

if [[ -f "$environment_file" ]]; then
  while IFS='=' read -r key value; do
    [[ -z "$key" || "$key" == \#* ]] && continue
    case "$key" in
      FRONTEND_IMAGE_TAG) frontend_tag="$value" ;;
      BACKEND_IMAGE_TAG) backend_tag="$value" ;;
      BANKS_IMAGE_TAG) banks_tag="$value" ;;
      TAPO) tapo_tag="$value" ;;
      *)
        echo "Unknown setting in $environment_file: $key" >&2
        exit 1
        ;;
    esac
  done < "$environment_file"
fi

case "$variable_name" in
  FRONTEND_IMAGE_TAG) frontend_tag="$image_tag" ;;
  BACKEND_IMAGE_TAG) backend_tag="$image_tag" ;;
  BANKS_IMAGE_TAG) banks_tag="$image_tag" ;;
  TAPO) tapo_tag="$image_tag" ;;
esac

temporary_file="$(mktemp "$cluster_root/.image-tags.env.XXXXXX")"
trap 'rm -f -- "$temporary_file"' EXIT
umask 077
{
  printf 'FRONTEND_IMAGE_TAG=%s\n' "$frontend_tag"
  printf 'BACKEND_IMAGE_TAG=%s\n' "$backend_tag"
  printf 'BANKS_IMAGE_TAG=%s\n' "$banks_tag"
  printf 'TAPO=%s\n' "$tapo_tag"
} > "$temporary_file"
mv -f -- "$temporary_file" "$environment_file"
trap - EXIT

printf 'Set %s to image tag %s.\n' "$component" "$image_tag"

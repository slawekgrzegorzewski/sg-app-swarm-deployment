#!/usr/bin/env bash
set -Eeuo pipefail

# Stages controller SSH keys from a Windows-mounted directory in WSL's /tmp.
# The resulting directory is printed on stdout for the Ansible wrapper.

ENVIRONMENT="${1:-}"
HOME_KEY_SOURCE="${2:-}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

is_wsl() {
  [[ -n "${WSL_INTEROP:-}" ]] || [[ "$(uname -r)" =~ [Mm]icrosoft|WSL ]]
}

usage() {
  cat <<EOF
Usage: $(basename "$0") test
       $(basename "$0") home <source-key-directory>

Stages the four private controller keys in a newly created WSL temporary
directory and prints that directory. The caller is responsible for removing it.

test  reads keys from ../ansible-test/.ssh relative to this script.
home  requires the directory containing pc2_ed25519, rpi5_ed25519,
      rpi4_ed25519 and rpi3_ed25519.
EOF
}

is_wsl || {
  echo "This helper must run inside WSL." >&2
  exit 1
}

case "$ENVIRONMENT" in
  test)
    [[ -z "$HOME_KEY_SOURCE" ]] || { usage >&2; exit 2; }
    HOME_KEY_SOURCE="$SCRIPT_DIR/../ansible-test/.ssh"
    key_names=(
      vagrant_pc2_ed25519
      vagrant_rpi5_ed25519
      vagrant_rpi4_ed25519
      vagrant_rpi3_ed25519
    )
    ;;
  home)
    [[ -n "$HOME_KEY_SOURCE" ]] || {
      echo "The source key directory is required for the home environment." >&2
      usage >&2
      exit 2
    }
    key_names=(pc2_ed25519 rpi5_ed25519 rpi4_ed25519 rpi3_ed25519)
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

[[ -d "$HOME_KEY_SOURCE" ]] || {
  echo "SSH key directory not found: $HOME_KEY_SOURCE" >&2
  exit 1
}

umask 077
staging_directory="$(mktemp -d "${TMPDIR:-/tmp}/sg-app-swarm-ansible-${ENVIRONMENT}-keys.XXXXXX")"

cleanup_on_error() {
  rm -rf -- "$staging_directory"
}
trap cleanup_on_error ERR

for key_name in "${key_names[@]}"; do
  source_key="$HOME_KEY_SOURCE/$key_name"
  [[ -f "$source_key" && -r "$source_key" ]] || {
    echo "SSH private key not found or unreadable: $source_key" >&2
    exit 1
  }

  install -m 600 -- "$source_key" "$staging_directory/$key_name"
done

trap - ERR
printf '%s\n' "$staging_directory"

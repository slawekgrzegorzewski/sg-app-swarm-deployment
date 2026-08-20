#!/usr/bin/env bash

ansible_wrapper_initialize() {
  local environment="$1"

  ANSIBLE_WRAPPER_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[1]}")" && pwd)"
  case "$environment" in
    home)
      ANSIBLE_WRAPPER_INVENTORY="$ANSIBLE_WRAPPER_DIR/inventories/home/hosts.yml"
      ANSIBLE_WRAPPER_DEFAULT_SSH_DIR="$HOME/.ssh/ansible-home"
      ;;
    test)
      ANSIBLE_WRAPPER_INVENTORY="$ANSIBLE_WRAPPER_DIR/inventories/test/hosts.yml"
      ANSIBLE_WRAPPER_DEFAULT_SSH_DIR="$HOME/.ssh/ansible-test"
      ;;
    *)
      echo "Unknown environment: $environment (expected home or test)" >&2
      exit 2
      ;;
  esac

  ANSIBLE_WRAPPER_USER="${ANSIBLE_TARGET_USER:-slawek}"
  ANSIBLE_WRAPPER_HOME_SSH_DIR="${ANSIBLE_HOME_SSH_DIR:-$ANSIBLE_WRAPPER_DEFAULT_SSH_DIR}"
  ANSIBLE_WRAPPER_KEY="${ANSIBLE_TARGET_KEY:--}"
}

ansible_wrapper_usage_overrides() {
  echo "Set ANSIBLE_TARGET_USER, ANSIBLE_TARGET_KEY, ANSIBLE_TARGET_LIMIT or ANSIBLE_HOME_SSH_DIR to override defaults."
}

ansible_wrapper_run() {
  local playbook="$1"
  local mode="$2"

  command -v ansible-playbook >/dev/null 2>&1 || {
    echo "ansible-playbook was not found." >&2
    exit 127
  }
  if [[ "$ANSIBLE_WRAPPER_KEY" != '-' ]]; then
    [[ -r "$ANSIBLE_WRAPPER_KEY" ]] || {
      echo "SSH private key not found: $ANSIBLE_WRAPPER_KEY" >&2
      exit 1
    }
  else
    [[ -d "$ANSIBLE_WRAPPER_HOME_SSH_DIR" ]] || {
      echo "SSH key directory not found: $ANSIBLE_WRAPPER_HOME_SSH_DIR" >&2
      exit 1
    }
  fi

  local -a command=(
    ansible-playbook "$playbook"
    -i "$ANSIBLE_WRAPPER_INVENTORY"
    -u "$ANSIBLE_WRAPPER_USER"
  )
  command+=(-e "ansible_home_ssh_dir=$ANSIBLE_WRAPPER_HOME_SSH_DIR")
  if [[ "$ANSIBLE_WRAPPER_KEY" != '-' ]]; then
    command+=(-e "ansible_private_key_file=$ANSIBLE_WRAPPER_KEY")
  fi
  if [[ -n "${ANSIBLE_TARGET_LIMIT:-}" ]]; then
    command+=(--limit "$ANSIBLE_TARGET_LIMIT")
  fi
  if [[ "$mode" == "check" ]]; then
    command+=(--check --diff)
  fi

  cd "$ANSIBLE_WRAPPER_DIR"
  ANSIBLE_CONFIG="$ANSIBLE_WRAPPER_DIR/ansible.cfg" "${command[@]}"
}

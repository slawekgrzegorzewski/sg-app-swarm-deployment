#!/usr/bin/env bash

ansible_wrapper_initialize() {
  local environment="$1"

  ANSIBLE_WRAPPER_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[1]}")" && pwd)"
  ANSIBLE_WRAPPER_PREPARED_SSH_DIR=""
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
  if ansible_wrapper_is_windows; then
    local -a prepare_command=(bash "$ANSIBLE_WRAPPER_DIR/prepare-test-ssh-keys-windows.sh" "$environment")
    if [[ "$environment" == "home" ]]; then
      [[ -n "${ANSIBLE_HOME_SSH_DIR:-}" ]] || {
        echo "On Windows, set ANSIBLE_HOME_SSH_DIR to the source directory containing the home SSH keys." >&2
        exit 2
      }
      prepare_command+=("$ANSIBLE_HOME_SSH_DIR")
    fi

    ANSIBLE_WRAPPER_PREPARED_SSH_DIR="$("${prepare_command[@]}")"
    ANSIBLE_WRAPPER_DEFAULT_SSH_DIR="$ANSIBLE_WRAPPER_PREPARED_SSH_DIR"
    ANSIBLE_WRAPPER_HOME_SSH_DIR="$ANSIBLE_WRAPPER_DEFAULT_SSH_DIR"
    trap ansible_wrapper_cleanup_prepared_ssh_dir EXIT
  else
    ANSIBLE_WRAPPER_HOME_SSH_DIR="${ANSIBLE_HOME_SSH_DIR:-$ANSIBLE_WRAPPER_DEFAULT_SSH_DIR}"
  fi
  ANSIBLE_WRAPPER_KEY="${ANSIBLE_TARGET_KEY:--}"
}

ansible_wrapper_is_windows() {
  [[ -n "${WSL_INTEROP:-}" ]] || [[ "$(uname -r)" =~ [Mm]icrosoft|WSL ]]
}

ansible_wrapper_cleanup_prepared_ssh_dir() {
  [[ -n "${ANSIBLE_WRAPPER_PREPARED_SSH_DIR:-}" ]] || return 0

  case "$ANSIBLE_WRAPPER_PREPARED_SSH_DIR" in
    /tmp/sg-app-swarm-ansible-*-keys.*)
      rm -rf -- "$ANSIBLE_WRAPPER_PREPARED_SSH_DIR"
      ANSIBLE_WRAPPER_PREPARED_SSH_DIR=""
      ;;
    *)
      echo "Refusing to remove an unexpected SSH key staging directory: $ANSIBLE_WRAPPER_PREPARED_SSH_DIR" >&2
      ;;
  esac
}

ansible_wrapper_usage_overrides() {
  echo "Set ANSIBLE_TARGET_USER, ANSIBLE_TARGET_KEY, ANSIBLE_TARGET_LIMIT or ANSIBLE_HOME_SSH_DIR to override defaults."
  if ansible_wrapper_is_windows; then
    echo "On Windows/WSL, test keys are staged automatically; home requires ANSIBLE_HOME_SSH_DIR as the source key directory."
  fi
}

ansible_wrapper_run() {
  local playbook="$1"
  local mode="$2"
  local -a extra_arguments=("${@:3}")

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
  command+=("${extra_arguments[@]}")
  if [[ "$mode" == "check" ]]; then
    command+=(--check --diff)
  fi

  cd "$ANSIBLE_WRAPPER_DIR"
  local exit_code=0
  set +e
  ANSIBLE_CONFIG="$ANSIBLE_WRAPPER_DIR/ansible.cfg" "${command[@]}"
  exit_code=$?
  set -e

  ansible_wrapper_cleanup_prepared_ssh_dir

  return "$exit_code"
}

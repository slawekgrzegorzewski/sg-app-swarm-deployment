# Ansible

The playbook prepares Debian and Ubuntu cluster hosts with a base Linux
configuration and Docker Engine. It does not join Docker Swarm, deploy
services, alter the firewall, or handle secrets.

Two inventories are provided:

* `inventories/home` — production hosts `PC2`, `rpi5`, `rpi4`, `rpi3`;
* `inventories/test` — the four Vagrant hosts addressed through their DNS
  names. They use the same logical host names as production: `PC2`, `rpi5`,
  `rpi4`, `rpi3`.

Shared variables for both environments live in `playbooks/group_vars`.
Keep environment-specific connection details in each inventory's `hosts.yml`
and `host_vars` directory.

The registry is accessed over HTTPS, so the role does not create
`/etc/docker/daemon.json` or configure insecure registries. Its certificate
must validate against the host trust store; for a private CA, install that CA
there instead of disabling registry verification.

Run the generic helper from this directory. It selects the inventory and SSH
key for the chosen environment:

```bash
./01-bootstrap.sh home --help
./01-bootstrap.sh test check
./01-bootstrap.sh test apply
./01-bootstrap.sh home check
./01-bootstrap.sh home apply
```

By default all hosts in the selected inventory are processed. Use
`ANSIBLE_TARGET_LIMIT` to target one host, for example
`ANSIBLE_TARGET_LIMIT=rpi3 ./01-bootstrap.sh home apply` or
`ANSIBLE_TARGET_LIMIT=rpi3 ./01-bootstrap.sh test apply`.

Preview changes:

```bash
./01-bootstrap.sh home check
```

Apply changes to the Raspberry Pi:

```bash
./01-bootstrap.sh home apply
```

The initial SSH connection must already work for the `slawek` user and that
user must have passwordless sudo access.

## SSH key and user

The `home` wrappers read production keys from `~/.ssh/ansible-home` by default
(`pc2_ed25519`, `rpi5_ed25519`, `rpi4_ed25519`, `rpi3_ed25519`). The `test`
wrappers read the per-node Vagrant keys from `~/.ssh/ansible-test`:
`vagrant_pc2_ed25519`, `vagrant_rpi5_ed25519`, `vagrant_rpi4_ed25519` and
`vagrant_rpi3_ed25519`.
Set `ANSIBLE_HOME_SSH_DIR` only when a wrapper should use another directory:

```bash
export ANSIBLE_HOME_SSH_DIR=/path/to/.ssh
./01-bootstrap.sh home apply
```

`ANSIBLE_TARGET_KEY` remains available as an explicit single-key override.

## Host-to-host SSH keys

To install each production host's own private key under
`~/.ssh/ansible-home`, after distributing all public keys, run:

```bash
./distribute-host-ssh-keys.sh apply
```

The script never copies every private key to every host. It maps `PC2`, `rpi5`,
`rpi4` and `rpi3` to their respective key pairs, and refuses to overwrite an
existing private key unless `--force` is passed explicitly.


## Docker Swarm

The Swarm playbook assumes that Docker Engine is already installed and
available on every host. It initializes the single manager (`PC2`) first and
then joins `rpi5`, `rpi4` and `rpi3` as workers:

```bash
export ANSIBLE_TARGET_KEY=/path/to/vagrant_pc2_ed25519
./02-docker-swarm.sh test check
./02-docker-swarm.sh test apply
```

The numbered wrapper is equivalent and also selects the inventory and key:

```bash
./02-docker-swarm.sh test check
./02-docker-swarm.sh test apply
```

The operation is idempotent for nodes already belonging to a Swarm. To leave
and recreate the test Swarm, run the explicitly destructive reset playbook:

```bash
./02a-docker-swarm-reset.sh test apply
```

Or using the numbered reset wrapper:

```bash
./02a-docker-swarm-reset.sh test apply
```

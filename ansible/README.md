# Ansible

The first playbook prepares RPi3 as a base Linux host. It does not install
Docker, join Docker Swarm, deploy services, alter the firewall, or handle
secrets.

The inventory uses `rpi3` as the SSH target. Change `ansible_host` in
`inventories/home/hosts.yml` to its LAN address if that name is not resolvable
from the Ansible control machine.

Run the playbook from this directory using the WSL helper script. Without an
argument, the script displays its help:

```bash
./wsl-bootstrap-rpi3.sh
```

Preview changes:

```bash
./wsl-bootstrap-rpi3.sh check
```

Apply changes to the Raspberry Pi:

```bash
./wsl-bootstrap-rpi3.sh apply
```

The initial SSH connection must already work for the `slawek` user and that
user must have passwordless sudo access.

## WSL helper script

From WSL, make the helper executable once:

```bash
chmod +x wsl-bootstrap-rpi3.sh
```

The script uses the `slawek` user and `~/.ssh/rpi3_ed25519` by default. Override
them when needed:

```bash
RPI3_ANSIBLE_USER=slawek \
RPI3_SSH_KEY=~/.ssh/rpi3_ed25519 \
./wsl-bootstrap-rpi3.sh apply
```

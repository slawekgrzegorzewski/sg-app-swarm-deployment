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

During `apply`, the bootstrap role installs and enables `systemd-timesyncd`.
It waits up to two minutes for NTP synchronization before continuing, which
ensures that Docker Swarm certificates are created and validated with a
consistent clock.

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

When a wrapper runs in WSL on Windows, it stages keys in a private directory
under WSL's `/tmp` and removes that directory after Ansible finishes. For
`test`, its source is always `../ansible-test/.ssh`. For `home`, provide the
source directory explicitly:

```bash
export ANSIBLE_HOME_SSH_DIR=/mnt/d/secure/ansible-home
./01-bootstrap.sh home apply
```

`ANSIBLE_TARGET_KEY` remains available as an explicit single-key override.

## Host-to-host SSH keys

Podczas uruchomienia playbooku `bootstrap-hosts.yml` rola `base_host` kopiuje
na każdy node wyłącznie jego własny klucz prywatny z katalogu kluczy kontrolera
Ansible. Nie kopiuje prywatnych kluczy pozostałych hostów.

* `home`: `~/.ssh/ansible-home/<nazwa-klucza>` na kontrolerze do
  `~/.ssh/ansible-home/` na nodzie;
* `test`: `~/.ssh/ansible-test/vagrant_<nazwa-hostu>_ed25519` na kontrolerze
  do `~/.ssh/ansible-test/` na nodzie.

Krok wymaga, aby na każdym nodzie były już obecne publiczne klucze wszystkich
pozostałych nodów w `~/.ssh/authorized_keys`. Dla `test` zapewnia to Vagrant;
dla `home` należy przygotować je przed pierwszym uruchomieniem playbooku.
Prywatne klucze są zapisywane z uprawnieniami `0600`, a ich katalog z `0700`.
Rola zarządza także blokiem w `~/.ssh/config`, ograniczonym do hostów klastra,
który wybiera właściwy lokalny klucz. Po bootstrappingu nie trzeba podawać
`-i`, np. `ssh slawek@ansible-test-swarm-node-1` w środowisku `test` albo
`ssh slawek@rpi5` w środowisku `home`. Pierwszy klucz hosta jest automatycznie
zapisywany w `known_hosts`; późniejsza zmiana tego klucza nadal przerywa
połączenie jako potencjalnie niebezpieczna.


## Docker Swarm

The Swarm playbook assumes that Docker Engine is already installed and
available on every host. It initializes the single manager (`PC2`) first and
then joins `rpi5`, `rpi4` and `rpi3` as workers:

Docker requires the Swarm advertise address to be a local IP address or
interface name, not a DNS name. The test inventory explicitly uses the VMs'
private `192.168.56.x` addresses. The default for other inventories is the
host's default IPv4 address; override `docker_swarm_advertise_addr` per host
when the cluster should use another network.

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

## Swarm node labels

After the Swarm is running, apply labels derived from the inventory groups:

```bash
./03-docker-swarm-labels.sh test check
./03-docker-swarm-labels.sh test apply
```

The playbook currently manages `postgres=true` and `registry=true`. The
`builder` label is intentionally not configured while builder nodes are
disabled. Repeating `apply` does not update nodes whose labels already match.

## Firewall

Configure the host firewall after Docker Swarm is running:

```bash
./04-firewall.sh test check
./04-firewall.sh test apply
./04-firewall.sh home check
./04-firewall.sh home apply
```

The home inventory limits Swarm traffic and PostgreSQL to `192.168.20.0/24`;
the test inventory uses `192.168.56.0/24`. Published HTTP, HTTPS and registry
ports (`80`, `443`, `5005`) are allowed externally. Docker-published ports may
bypass UFW through Docker's iptables rules, so production restrictions for
published ports must also be enforced in the `DOCKER-USER` chain.

Or using the numbered reset wrapper:

```bash
./02a-docker-swarm-reset.sh test apply
```

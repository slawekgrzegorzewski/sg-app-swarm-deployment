# Ansible

The bootstrap playbook prepares Debian and Ubuntu cluster hosts with a base
Linux configuration and Docker Engine. Dedicated playbooks manage the Docker
Swarm, firewall, Let's Encrypt tooling, and Docker Swarm secrets. They do not
deploy application services.

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

## Let's Encrypt

The dedicated playbook installs Certbot plus a renewal script on every host in
the `letsencrypt_hosts` group (`PC2` in the `home` inventory). During a
request, its authenticator writes Certbot's HTTP-01 token under the Nginx
webroot; its cleanup hook removes that token afterwards. A successful request
copies `fullchain.pem` and `privkey.pem` to the files used to create the
gateway's Docker Swarm secrets.

Install or update the scripts:

```bash
./05-letsencrypt.sh home apply
```

With the gateway running and all configured domains publicly reachable on
port 80, request or renew the certificate on `PC2`:

```bash
sudo /usr/local/sbin/renew-application-certs
```

To test the HTTP-01 validation flow without obtaining, saving, or deploying a
production certificate, use Let's Encrypt's staging server:

```bash
sudo /usr/local/sbin/renew-application-certs --dry-run --force-renewal
```

`--force-renewal` ensures that the validation is exercised even when the current
certificate is not close to expiry. In dry-run mode the script does not copy
certificate files to the Docker Swarm secrets directory.

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

It also creates the shared swarm-scoped overlay networks `cluster_network`
and `sg_app_network`. Application stacks use these networks as external
resources, so they are available before any stack is deployed.

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

## Docker Swarm secrets

The secrets step creates or updates Swarm secrets on the manager from the
references in `roles/docker_swarm_secrets/defaults/main.yml`. It uses the
local 1Password CLI (`op read`) on the Ansible controller. Ansible sends each
value to `docker secret create` on the manager through standard input, with the
value protected by `no_log`. The manager does not need the 1Password CLI or
1Password credentials. Before making changes, the role checks all Swarm
services. An existing secret is recreated only when no service uses it;
otherwise the play fails before changing any secrets. Because Docker does not
expose stored secret values, every existing unused managed secret is recreated
during `apply`.

Install and authenticate the 1Password CLI on the computer that runs Ansible.
Desktop-app integration, `op signin`, or a narrowly scoped service-account
token can provide the local CLI session. The token is not stored in the
repository or Ansible inventory. In WSL, the wrapper automatically finds a
Windows installation of `op.exe` when no native `op` command exists. Set
`ONEPASSWORD_CLI` to override the detected executable.

```bash
export OP_SERVICE_ACCOUNT_TOKEN='...'
./06-docker-secrets.sh home check
./06-docker-secrets.sh home apply
```

### Test-only secret reader

The test inventory includes a one-shot Swarm service that mounts every managed
secret and writes its name and value to the service logs. This intentionally
exposes secret values and must never be deployed in the home environment.

After creating the test secrets, stream the Compose file from the Ansible
controller to the test manager:

```bash
./06-docker-secrets.sh test apply
ssh ansible-test-swarm-manager \
  'docker stack deploy --compose-file - docker-secrets-test' \
  < inventories/test/docker-secrets-test/docker-compose.yml
```

PowerShell, run from the `ansible` directory:

```powershell
wsl.exe -d Ubuntu -- ./06-docker-secrets.sh test apply

$composePath = 'inventories/test/docker-secrets-test/docker-compose.yml'
$composePath = (Resolve-Path $composePath).Path

Push-Location '..\ansible-test'
try {
    Get-Content -Raw -Encoding utf8 $composePath |
        vagrant.exe ssh swarm-manager -c `
            'sudo docker stack deploy --compose-file - docker-secrets-test'
}
finally {
    Pop-Location
}
```

Read the output and remove the test stack when finished:

```bash
ssh ansible-test-swarm-manager \
  'docker service logs --raw docker-secrets-test_secret-printer'
ssh ansible-test-swarm-manager 'docker stack rm docker-secrets-test'
```

PowerShell:

```powershell
Push-Location '..\ansible-test'
try {
    vagrant.exe ssh swarm-manager -c `
        'sudo docker service logs --raw docker-secrets-test_secret-printer'
    vagrant.exe ssh swarm-manager -c `
        'sudo docker stack rm docker-secrets-test'
}
finally {
    Pop-Location
}
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

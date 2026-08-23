# Swarm release sources

The release inputs are packaged without changing their layout:

```text
stacks/       Docker Swarm Compose files
configs/      files uploaded to Swarm as versioned Docker configs
tools/        manager-only operational commands
```

`application/secrets/setup_secrets.sh` is retained unchanged as a legacy
reference and is deliberately excluded from the archive. `utils/` contains
the release installer used by CI and is transferred next to the archive.
The two scripts under `infrastructure/management` are also legacy references;
the release no longer installs host cron entries.

Runtime directories are not created by these scripts. Ansible derives them
from inventory workload groups under `/srv/cluster`. The release archive is
installed only on the Swarm manager as `/srv/cluster/releases/<release-id>`;
`/srv/cluster/current` points at the active release.

Use `/srv/cluster/current/tools/start-all.sh` to reconcile all stacks or
`start-stack.sh <name>` for one of `core`, `database`, `application`, and
`infrastructure`.

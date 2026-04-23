# Vagrant scaffold — Ubuntu deploy target

This folder contains a **provider-agnostic Vagrant scaffold** for a future
Ubuntu-based deployment VM that will eventually host Docker workloads
deployed through a CircleCI workflow.

## What this scaffold IS

- A Vagrantfile that boots an Ubuntu box and runs four small, idempotent
  provisioning scripts (`bootstrap`, `install_docker`, `configure_user`,
  `verify_setup`).
- A deliberately minimal layout that is easy to extend.
- Safe to commit: contains no secrets.

## What this scaffold is intentionally NOT (yet)

- **No provider is chosen.** The Vagrantfile does not activate a Hyper-V
  or VirtualBox block — both are shown as commented examples. You pick
  one later.
- **No host configuration changes.** Nothing here enables Hyper-V,
  touches WSL, installs Vagrant, installs VirtualBox, or modifies BIOS /
  Windows features.
- **No CircleCI runner is installed.** The runner provisioner is only a
  placeholder in the `Vagrantfile` comments.
- **No secrets.** `env/example.env` is a template; a real `.env` is
  gitignored.
- **No application ports, image names or database credentials** are
  hardcoded anywhere.

## What still depends on the provider choice

These decisions cannot be finalized until you pick Hyper-V or VirtualBox:

- Which `config.vm.provider` block to uncomment in the `Vagrantfile`.
- Whether to use `bento/ubuntu-22.04` (works on both) or a
  Hyper-V-specific box.
- The networking mode (`private_network` type/IP).
- The synced-folder strategy (Hyper-V commonly needs SMB; VirtualBox
  works with the default share).
- Whether to invoke `vagrant` from Windows or from WSL.

## Usage (once a provider has been chosen)

```bash
# From this directory, after uncommenting the correct provider block:
vagrant up --provider=virtualbox    # or: --provider=hyperv

# SSH into the VM:
vagrant ssh

# Re-run provisioning scripts without recreating the VM:
vagrant provision

# Re-run just one provisioner:
vagrant provision --provision-with install-docker

# Halt the VM:
vagrant halt

# Destroy the VM (irreversible):
vagrant destroy -f
```

Environment variables (see `env/example.env`) let you override the box,
hostname, CPU, memory, and sync paths without editing the `Vagrantfile`.

## Layout

```
infra/vagrant/
├── Vagrantfile
├── README.md
├── .gitignore
├── env/
│   └── example.env
└── scripts/
    ├── bootstrap.sh
    ├── install_docker.sh
    ├── configure_user.sh
    └── verify_setup.sh
```

And, at the repository root, for future deployment work:

```
deploy/
└── README.md
docker-compose.deploy.yml
```

## Later steps for CircleCI

These are deferred until the workshop provides the necessary decisions
and credentials:

- [ ] **CircleCI machine runner** — install + register inside the VM
      (`scripts/install_circleci_runner.sh`, gated on
      `CIRCLECI_RUNNER_TOKEN` and `CIRCLECI_RUNNER_RESOURCE_CLASS`).
- [ ] **Docker image deployment** — pull/build strategy, registry login,
      image name and tag convention (see TODOs in
      `docker-compose.deploy.yml`).
- [ ] **Secrets management** — decide between CircleCI contexts, SSH'd
      `.env` files under `/opt/deploy/env`, or a secrets manager. No
      secrets live in this repo.
- [ ] **Application compose stack** — finalize services, ports, volumes,
      and healthchecks in `docker-compose.deploy.yml` under `deploy/`.

# Running Vagrant on Windows (Hyper-V provider)

This is the runbook for bringing up the deploy VM. You run these
commands from **Windows PowerShell**, not from WSL.

## Prerequisites (one time)

1. **Hyper-V enabled.** Open Hyper-V Manager to confirm. (Already done.)
2. **Vagrant installed on Windows.** Download from
   <https://developer.hashicorp.com/vagrant/install>. (Already done.)
3. **PowerShell run as Administrator.** Hyper-V management requires
   elevation. Right-click PowerShell -> "Run as administrator".
4. **Git clone the repo on Windows too, OR access it via the WSL path.**
   Both work. Recommended: use the same path you already have on WSL, e.g.
   `D:\temp\ci_cd_for_a_to-do_app\`.

## First boot

Open **elevated PowerShell**:

```powershell
cd D:\temp\ci_cd_for_a_to-do_app\infra\vagrant
vagrant up --provider=hyperv
```

What happens on first run:

1. Vagrant downloads the `bento/ubuntu-22.04` box (~500 MB).
2. Hyper-V creates a linked-clone VM named `deploy-target`.
3. The VM boots, Vagrant SSHes in.
4. The four provisioner scripts run **inside** the VM, in order:
   `bootstrap.sh` -> `install_docker.sh` -> `configure_user.sh` ->
   `verify_setup.sh`.
5. `verify_setup.sh` prints versions and exits 0 if Docker is healthy.

Expect ~5-10 minutes end-to-end on the first run.

## Day-to-day commands

```powershell
# From D:\temp\ci_cd_for_a_to-do_app\infra\vagrant

vagrant status                      # what state is the VM in?
vagrant ssh                         # open a shell inside the VM
vagrant halt                        # graceful shutdown
vagrant up                          # boot it back up (provisioners skipped)
vagrant provision                   # re-run ALL provisioner scripts
vagrant provision --provision-with install-docker   # re-run ONE
vagrant reload                      # halt + up (picks up Vagrantfile changes)
vagrant destroy -f                  # delete the VM entirely
```

## Inside the VM

Once you `vagrant ssh`, you're the `vagrant` user on Ubuntu 22.04.
Useful first checks:

```bash
docker --version
docker compose version
systemctl is-active docker
ls -la /opt/deploy                  # directory layout created by configure_user.sh
```

## Getting the repo inside the VM

Because synced folders are **disabled by default** on Hyper-V (see the
Vagrantfile comments for why), you clone the repo from within the VM:

```bash
# inside vagrant ssh
sudo apt-get install -y git   # already installed by bootstrap.sh
git clone https://github.com/<your-gh-user>/<your-fork>.git
cd <your-fork>
```

From there you can test the compose stack exactly like you did on WSL:

```bash
cp .env.example .env          # edit passwords
docker compose up -d
curl -s http://127.0.0.1:3000/items
```

## Finding the VM's IP

Default Switch gives out dynamic NAT IPs. Vagrant usually handles this
transparently, but if you want to know it:

```powershell
# From Windows
vagrant ssh -- -O 'forward 127.0.0.1:3000:localhost:3000'
# or, simpler: forward a port ad-hoc:
vagrant ssh -- -L 3000:localhost:3000
# then open http://127.0.0.1:3000/ in your Windows browser
```

## Common issues

- **"Hyper-V could not initialize memory."** Lower `VAGRANT_MEMORY` in
  `env\example.env` (copy to `.env` first), or close memory-hungry apps.
- **"No Hyper-V switch available."** Shouldn't happen since the Default
  Switch always exists on Windows 10/11 with Hyper-V enabled, but if it
  does: create an External Switch in Hyper-V Manager.
- **Provisioner fails with `/bin/bash^M: bad interpreter`.** Line endings.
  Make sure your git preserves LF for `*.sh` (we have `.gitattributes`
  enforcing this). Fix: from WSL, `dos2unix infra/vagrant/scripts/*.sh`
  and re-commit.
- **`vagrant up` hangs at "Waiting for machine to boot"** for >5 min. Try
  `vagrant halt -f` then `vagrant up` again. Hyper-V sometimes doesn't
  report the initial IP to Vagrant on cold boots.
- **UAC prompts every command.** Expected. Elevated PowerShell is
  required for Hyper-V. If it's annoying, launch PowerShell once elevated
  and keep the window open.

## What NOT to do on Windows

- Don't install VirtualBox alongside Hyper-V. They fight over the
  hypervisor.
- Don't disable Hyper-V to "free up" the hypervisor -- WSL2 also uses it.
- Don't run `vagrant` from WSL. You already tried and hit connection
  issues; Windows-side Vagrant is the committed path.

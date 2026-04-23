# Self-hosted CircleCI runner on the Vagrant VM

This wires your Vagrant VM up as a CircleCI self-hosted runner so the
`deploy` job (added in Step 7) can execute *on the VM* against localhost
Docker.

## Concepts (5-minute version)

- **Namespace**: a globally-unique name under your CircleCI org. Lives
  forever, you get one per org. Usually your GitHub user/org name.
- **Resource class**: a label under your namespace, e.g.
  `yourname/deploy-vm`. Jobs in `.circleci/config.yml` can target a
  resource class with `resource_class: yourname/deploy-vm`. Any runner
  holding that class's token will pick up the job.
- **Runner token**: per-resource-class secret. Proves a specific runner
  instance is allowed to execute jobs for that class.
- **Runner agent** (`circleci-runner` binary): the daemon on the VM
  that polls CircleCI's API, receives jobs, runs them, reports back.
  Outbound HTTPS only -- no inbound ports needed.

## Prerequisites

- VM already up and healthy from Step 3 (`vagrant status` = running).
- `docker-hub` Context already working from Step 5.
- An account at <https://app.circleci.com/> with the project set up.

---

## 1. Create a CircleCI namespace

**Choose carefully -- this is globally unique and cannot be renamed.**
A common pattern is your GitHub username or org name, e.g.
`long-term-effects-of-suffering` (lowercase, dashes, no spaces).

**UI path:**

1. <https://app.circleci.com/> -> Organization Settings -> **Namespaces**.
2. **Create Namespace**.
3. Pick a name, confirm.

## 2. Create a resource class

**UI path:**

1. Organization Settings -> **Self-Hosted Runners** -> **Create Resource Class**.
2. Namespace: select the one from step 1.
3. Resource class name: `deploy-vm` (short, descriptive).
4. Click **Create**.
5. **Copy the runner token** that appears -- shown ONCE. Save it somewhere
   temporary (you'll paste it into PowerShell in a moment; then discard it).

You'll end up with a fully qualified resource class like:
`long-term-effects-of-suffering/deploy-vm`. Remember this -- it goes
into `.circleci/config.yml` in Step 7.

## 3. Install the runner on the VM

From **elevated PowerShell** on Windows:

```powershell
cd D:\temp\ci_cd_for_a_to-do_app\infra\vagrant

# Paste the token you got in step 2:
$env:CIRCLECI_RUNNER_TOKEN = "<paste-token-here>"

# (optional, defaults to VM hostname "deploy-target")
# $env:CIRCLECI_RUNNER_NAME = "deploy-target"

# Trigger the opt-in provisioner:
vagrant provision --provision-with circleci-runner
```

What this does:

1. Downloads `circleci-runner` into `/usr/local/bin/` on the VM.
2. Writes `/etc/circleci-runner/circleci-runner-config.yaml` with the
   token (permissions 0600, root-only).
3. Installs `/etc/systemd/system/circleci-runner.service`.
4. Enables and starts the service.
5. Verifies it's active.

Expect ~30 seconds.

## 4. Verify from the VM

```powershell
vagrant ssh
```

Inside the VM:

```bash
# Service is running and enabled on boot?
systemctl is-active circleci-runner
systemctl is-enabled circleci-runner

# Logs
sudo journalctl -u circleci-runner --no-pager | tail -20
# Expect to see "Runner started" or similar.

# Binary is in place?
which circleci-runner
circleci-runner --version
```

## 5. Verify from CircleCI's UI

<https://app.circleci.com/> -> Organization Settings -> **Self-Hosted Runners**
-> your resource class -> **Runners** tab.

You should see one runner listed, name = `deploy-target` (or whatever
you set `CIRCLECI_RUNNER_NAME` to), status **Online / Idle**.

If it says Offline after a minute, see Troubleshooting below.

## 6. What to do next

Nothing here -- you've set up the infrastructure. Step 7 adds the
`deploy` job to `.circleci/config.yml` and targets this resource class.

## Troubleshooting

### Runner stays "Offline" in the CircleCI UI

```bash
sudo systemctl status circleci-runner
sudo journalctl -u circleci-runner -n 100 --no-pager
```

Common causes:

- **`401 Unauthorized`**: wrong or revoked token. Re-create the resource
  class, get a new token, re-run the provisioner.
- **`no route to host` / DNS failures**: VM has no outbound internet.
  Check Hyper-V Default Switch is still attached.
- **`permission denied` on docker**: the `vagrant` user isn't in the
  `docker` group. Should be handled by `configure_user.sh`. Fix:
  `sudo usermod -aG docker vagrant && sudo systemctl restart circleci-runner`.

### "CIRCLECI_RUNNER_TOKEN is not set"

You didn't set `$env:CIRCLECI_RUNNER_TOKEN` before running
`vagrant provision`. Set it and retry.

### You lost the token

Tokens can't be recovered. In the CircleCI UI, delete the resource
class's token and create a new one. Re-run the provisioner with the
new token.

### You want to uninstall the runner

On the VM:

```bash
sudo systemctl stop circleci-runner
sudo systemctl disable circleci-runner
sudo rm /etc/systemd/system/circleci-runner.service
sudo rm -rf /etc/circleci-runner /var/lib/circleci-runner /var/log/circleci-runner
sudo rm /usr/local/bin/circleci-runner
sudo systemctl daemon-reload
```

Then delete the resource class in the CircleCI UI.

## Security notes

- The token grants job-execution rights on the VM. Treat it like a
  password. It's stored in `/etc/circleci-runner/...yaml` at 0600
  root-only; nothing on the VM reads it except root.
- The runner executes arbitrary commands from your `.circleci/config.yml`.
  Anyone with push access to your GitHub repo can make this VM run
  their code. Guard your repo accordingly.
- The runner makes **only outbound** HTTPS connections to
  `runner.circleci.com`. No inbound firewall rules are required.

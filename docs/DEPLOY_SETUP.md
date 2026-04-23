# Step 7 -- wiring the deploy job

The deploy job runs on the Vagrant VM via the self-hosted runner you set
up in Step 6. It pulls the freshly-built image, (re)starts the compose
stack, and smoke-tests `/items`.

## 1. Set the resource class

The `deploy` job in `.circleci/config.yml` has a literal
`resource_class:` value:

```yaml
deploy:
  machine: true
  resource_class: braz9LKDI/deploy-vm
```

If your namespace or class name is different, update that string. You
can find the exact value in CircleCI UI -> Organization Settings ->
Self-Hosted Runners.

**Note on escaping:** CircleCI 2.1 treats `<<` as parameter syntax, so
the heredocs in the deploy job are written `\<<EOF` (with a backslash).
This is a CircleCI quirk, not bash -- at runtime bash sees a normal
`<<EOF`.

## 2. Re-run the runner provisioner

The runner install script was updated to chown `/opt/deploy` to the
`circleci` user so the deploy job doesn't need sudo. Apply it:

```powershell
# From elevated PowerShell in infra\vagrant:
$env:CIRCLECI_RUNNER_TOKEN = "<same-token-as-before>"
vagrant provision --provision-with circleci-runner
```

Verify on the VM:

```bash
vagrant ssh
stat -c '%U:%G %a %n' /opt/deploy /opt/deploy/env
# both should show: circleci:circleci ...
```

## 3. Create the `deploy-secrets` Context in CircleCI

CircleCI UI -> Organization Settings -> **Contexts** -> **Create Context**.

- Name: `deploy-secrets` (exact match -- referenced in config.yml).
- Add four environment variables (pick strong values; these ARE the DB
  passwords for your deployed stack):

| Name | Example value | Notes |
|---|---|---|
| `MYSQL_ROOT_PASSWORD` | `gE7K...` (16+ random chars) | For mysql container only |
| `MYSQL_DATABASE`      | `todos`                     | App DB name |
| `MYSQL_USER`          | `todos_app`                 | NOT root; app connects as this |
| `MYSQL_PASSWORD`      | `tV9m...` (16+ random chars)| `todos_app`'s password |

Generate strong values however you like:

```bash
openssl rand -base64 24
```

## 4. Commit and push

```bash
git add .circleci/config.yml infra/vagrant/scripts/install_circleci_runner.sh docs/DEPLOY_SETUP.md
git commit -m "feat(ci): add deploy job targeting self-hosted runner"
git push
```

## 5. Watch the pipeline

<https://app.circleci.com/pipelines/> -> your project -> latest.

Expected order:

1. `test` -- green on any branch.
2. `build_and_push` -- green on main; pushes `<sha>` and `latest` to
   Docker Hub.
3. `deploy` -- queued on the `REPLACE_ME/deploy-vm` resource class.
   Your self-hosted runner picks it up within ~30s and starts executing.

**First-run deploy takes 1-3 minutes** because:

- It pulls `mysql:8.0` (~250 MB, one-time).
- It pulls your app image (~175 MB, one-time).
- It waits for MySQL's healthcheck (~20s).
- Then the app starts and the smoke test runs.

## 6. Verify from outside CI

From the VM (`vagrant ssh`):

```bash
docker ps
# should show todo_app + todo_mysql, both healthy

curl -s http://127.0.0.1:3000/items
# [] or existing items
```

From Windows (if you want browser access):

```powershell
# Forward VM port 3000 to Windows localhost:3000
vagrant ssh -- -L 3000:localhost:3000 -N
# Now http://127.0.0.1:3000/ works in your browser
```

## 7. Subsequent deploys

Just push to `main`. The pipeline will:

1. Run tests.
2. Build + push a new image with the new short-SHA tag.
3. Deploy that SHA tag to the VM. MySQL volume persists, so your data
   survives the swap.

Rolling back = revert the commit and push. Pipeline deploys the prior
image automatically.

## Troubleshooting

### Deploy job stuck "Queued" forever

Runner isn't online OR `resource_class` in config.yml doesn't match the
actual resource class name. Check both:

```bash
# On the VM:
systemctl is-active circleci-runner
```

And confirm in CircleCI UI that the runner is "Online".

### `permission denied on /var/run/docker.sock`

The `circleci` user isn't in the `docker` group. Re-run the provisioner
(step 2 above) -- the script adds the group and restarts the service.

### `env file /opt/deploy/env/*.env not found`

The "Seed" step failed. Check that the `deploy-secrets` Context is wired
on the deploy job (workflow block -- `context: - deploy-secrets`).

### MySQL refuses connection

Most common: password changed between deploys but the `todo_mysql_data`
volume still has the OLD password baked in (MySQL only initializes users
on FIRST run). Fix: `docker compose -f docker-compose.deploy.yml down -v`
on the VM, next deploy reinitializes. **Loses existing data.**

### Smoke test fails but containers look healthy

`curl http://127.0.0.1:3000/items` from inside the VM. If that works but
the CI step fails, it's an IP binding issue. Check `docker compose ps`
shows `0.0.0.0:3000->3000/tcp`.

# To-Do App -- CI/CD workshop project

A minimal Node.js to-do list app, used as the subject of an end-to-end
CI/CD pipeline: **GitHub push -> CircleCI cloud (tests, build, push to
Docker Hub) -> self-hosted runner on a Vagrant VM (deploy via Docker
Compose) -> live app**.

The app itself is almost incidental. The point of this repo is the
pipeline around it: a realistic "code commit to running container"
loop that you can stand up on a single Windows host with Hyper-V.

## Architecture at a glance

```
  developer push
      |
      v
  GitHub (main)
      |
      +--> webhook -----> CircleCI Cloud
                              |
                              |   job: test       (cloud Node executor)
                              |   job: build_and_push (cloud machine, Docker Hub)
                              |
                              +--> job: deploy    (self-hosted runner
                                                   -- runs ON the VM --
                                                   docker compose pull+up
                                                   smoke-test GET /items)
```

Everything runs on one Windows machine:

- **CircleCI Cloud** kicks off jobs in response to GitHub webhooks.
- **Docker Hub** (`br4z/to-do_app`) stores built images keyed by short SHA.
- **Vagrant VM** (`deploy-target`, Ubuntu 22.04, Hyper-V) hosts the
  self-hosted runner and the deployed compose stack (app + MySQL 8).

## Repo layout

```
src/                     Node app (Express + mysql / sqlite persistence)
spec/                    Jest test suites
Dockerfile               Multi-stage build for production image
docker-compose.yml       LOCAL dev stack (builds from source)
docker-compose.deploy.yml DEPLOY stack (pulls image from Docker Hub)
deploy/env/              Example env files (.env.example committed;
                         real values in /opt/deploy/env/ on the VM)
.circleci/config.yml     3-job pipeline: test / build_and_push / deploy
infra/vagrant/
  Vagrantfile            Hyper-V VM definition (Ubuntu 22.04, 4 GB, 2 CPU)
  scripts/               Idempotent provisioners:
    install_docker.sh      - Docker Engine + Compose plugin
    configure_user.sh      - vagrant user in docker group, /opt/deploy/
    verify_setup.sh        - sanity-check after boot
    install_circleci_runner.sh  - (opt-in) self-hosted runner agent
docs/                    Step-by-step runbooks (see below)
```

## Documentation

Each phase of the setup has its own runbook. Read in order if you're
rebuilding from scratch:

| Doc | What it covers |
|---|---|
| [`docs/VAGRANT_WINDOWS.md`](docs/VAGRANT_WINDOWS.md) | Bringing up the Hyper-V VM with Vagrant on Windows |
| [`docs/TESTING.md`](docs/TESTING.md) | Running the Jest suite locally and in CI |
| [`docs/CI_SETUP.md`](docs/CI_SETUP.md) | CircleCI project setup, `docker-hub` Context |
| [`docs/RUNNER_SETUP.md`](docs/RUNNER_SETUP.md) | Namespace, resource class, self-hosted runner install |
| [`docs/DEPLOY_SETUP.md`](docs/DEPLOY_SETUP.md) | `deploy-secrets` Context, deploy job, verification |

## Local quickstart (no VM needed)

### Run the tests

```bash
npm install
npm test
```

All suites (unit + integration + e2e with supertest) run against an
in-memory sqlite DB. No MySQL required.

### Run the app locally

```bash
npm install
npm run dev          # sqlite mode -- DB at ./data/todo.db
# open http://localhost:3000/
```

### Run the dev stack with Docker Compose (app + MySQL)

```bash
cp .env.example .env       # then edit passwords
docker compose up --build
# app at http://localhost:3000/, MySQL internal-only
```

## Full pipeline quickstart

1. **Provision the VM** -- `docs/VAGRANT_WINDOWS.md`.
2. **Wire CircleCI** -- `docs/CI_SETUP.md`. After this, pushes to `main`
   run `test` + `build_and_push` green. Image lands on Docker Hub.
3. **Install the runner** -- `docs/RUNNER_SETUP.md`. Runner shows Online
   in CircleCI UI.
4. **Add the deploy secrets + kick off a deploy** --
   `docs/DEPLOY_SETUP.md`. Push to `main` now runs all three jobs; last
   one leaves a live app on `http://<vm>:3000/`.

## What the pipeline guarantees

- **Every commit** on any branch runs the full test suite.
- **Every merge to `main`** produces a Docker Hub image tagged with the
  short git SHA *and* `latest`.
- **Every `main` merge or `v*.*.*` tag** redeploys the new image onto the
  VM and proves the app is healthy by hitting `GET /items` before the
  pipeline goes green.
- **Rollback** is `git revert && git push` -- the prior image redeploys
  automatically. MySQL data survives because the volume is persistent.

## Secrets flow

Nothing secret is in this repo. Everything is injected at the moment of
need:

| Secret | Where it's stored | Where it's used |
|---|---|---|
| `DOCKERHUB_USERNAME` / `DOCKERHUB_TOKEN` | CircleCI Context `docker-hub` | `build_and_push` job (push); `deploy` job (pull) |
| `MYSQL_ROOT_PASSWORD`, `MYSQL_DATABASE`, `MYSQL_USER`, `MYSQL_PASSWORD` | CircleCI Context `deploy-secrets` | `deploy` job writes them into `/opt/deploy/env/*.env` on the VM (mode 0600) |
| CircleCI runner token | `/etc/circleci-runner/circleci-runner-config.yaml` on the VM (mode 0640 root:circleci) | systemd starts the runner with this token |

`/opt/deploy/env/` and `data/` are in `.gitignore`.

## Tech stack

- **App**: Node.js 18, Express, Jest/Supertest
- **Persistence**: MySQL 8 in prod; sqlite fallback for local dev + tests
- **Container**: multi-stage Dockerfile, non-root `node` user, healthcheck
  on `/items`
- **CI**: CircleCI 2.1 config -- cloud executors for test/build, self-hosted
  machine runner for deploy
- **Deploy target**: Ubuntu 22.04 on Hyper-V, provisioned by Vagrant

## Contributing / iterating

- Keep secrets out of the repo. The `.env.example` and
  `deploy/env/*.env.example` files are the authoritative templates.
- If you change `docker-compose.deploy.yml`, make sure the dev
  `docker-compose.yml` still works too -- they share a lot of shape.
- Tests should run offline and in seconds. If you need MySQL for a new
  test, put it in `spec/integration/` and let the sqlite fallback keep
  the unit suite fast.

## License

Uses the Docker / getting-started-app sample as a starting point
(Apache 2.0). Everything added in this repo is released under the same
license unless noted otherwise.

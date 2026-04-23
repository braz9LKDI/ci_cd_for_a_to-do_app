# Manual testing & Docker Hub push

This doc walks through every local check you can run today, **before any
CircleCI or Vagrant work**. Everything here is done from your WSL (Arch)
shell with Docker running locally.

Nothing here is destructive to your host beyond pulling base images and
creating Docker volumes (which we clean up at the end).

---

## 0. Prerequisites

```bash
sudo systemctl start docker          # if not already running
docker version --format '{{.Server.Version}}'   # should print a version
```

You should be in the repo root:

```bash
pwd    # .../ci_cd_for_a_to-do_app
```

---

## 1. Run the tests on the host (fast path)

This uses your host's Node/npm. Good for the inner dev loop.

```bash
npm install          # first time only
npm test
```

Expected:

```
Test Suites: 6 passed, 6 total
Tests:       11 passed, 11 total
```

---

## 2. Build the Docker image

The Dockerfile has three stages: `deps`, `test`, `runtime`.

### 2a. Build + run the test stage (tests inside the container)

```bash
docker build --target test -t to-do_app:test .
```

This fails the build if any test fails. The image produced is a
throwaway; you don't need to run it.

### 2b. Build the runtime image

```bash
docker build --target runtime -t br4z/to-do_app:local .
```

Verify the result:

```bash
docker image ls br4z/to-do_app
# REPOSITORY       TAG     SIZE
# br4z/to-do_app   local   ~174MB
```

---

## 3. Run the full stack with Docker Compose

### 3a. Prepare secrets

```bash
cp .env.example .env
# Edit .env and set non-trivial passwords if you want
```

`.env` is gitignored — it will never be committed.

### 3b. Bring the stack up

```bash
docker compose up -d
```

First run pulls `mysql:8.0` (~250 MB), ~1 min. Subsequent runs are instant.

### 3c. Verify both containers are healthy

```bash
docker compose ps
```

Expect both `todo_mysql` and `todo_app` to show `Up ... (healthy)`.
MySQL becomes healthy first (~20 s), then the app starts.

### 3d. Hit the API

```bash
# List (should be empty on first run)
curl -s http://127.0.0.1:3000/items
# []

# Create
curl -s -X POST -H 'Content-Type: application/json' \
  -d '{"name":"buy milk"}' \
  http://127.0.0.1:3000/items
# {"id":"...uuid...","name":"buy milk","completed":false}

# List again
curl -s http://127.0.0.1:3000/items
# [{"id":"...","name":"buy milk","completed":false}]
```

### 3e. Open the UI

Visit <http://127.0.0.1:3000/> in your browser. The static frontend from
`src/static/` is served at `/` and talks to the same `/items` API.

### 3f. Inspect logs if anything looks wrong

```bash
docker compose logs app    | tail -30
docker compose logs mysql  | tail -30
```

### 3g. Tear down

```bash
docker compose down          # stops + removes containers, KEEPS the volume
# or:
docker compose down -v       # also removes todo_mysql_data (wipes DB)
```

---

## 4. Push the image to Docker Hub (manual)

This proves the full chain **image → registry → pull from anywhere** works
before we hand it off to CircleCI. No CI is required for this step.

### 4a. Create a Docker Hub access token

1. <https://hub.docker.com/> → Account Settings → **Security** → **New Access Token**.
2. Description: `workshop-local` (or anything).
3. Permissions: **Read, Write, Delete** (Delete is optional).
4. Copy the token string **now** — Docker Hub only shows it once.

**Do not use your Docker Hub password.** Tokens can be revoked individually
and have scoped permissions.

### 4b. Log in from your shell

```bash
docker login -u br4z
# Password: <paste the access token, NOT your hub.docker.com password>
```

The token is cached in `~/.docker/config.json` as base64 (not encrypted).
That's fine for a dev laptop; on servers use a credential helper.

### 4c. Tag the image

A good first push uses **two tags** for the same image — a specific one
and `latest`:

```bash
# Build first if you haven't already
docker build --target runtime -t br4z/to-do_app:local .

# Add two "real" tags pointing to that image ID
docker tag br4z/to-do_app:local br4z/to-do_app:0.1.0
docker tag br4z/to-do_app:local br4z/to-do_app:latest
```

Confirm:

```bash
docker image ls br4z/to-do_app
```

You should see three tags (`local`, `0.1.0`, `latest`) all sharing the
same IMAGE ID.

### 4d. Push

```bash
docker push br4z/to-do_app:0.1.0
docker push br4z/to-do_app:latest
```

First push uploads all layers (~60 MB over the wire for this image).
Subsequent pushes only upload changed layers.

### 4e. Verify it landed

- Web: <https://hub.docker.com/r/br4z/to-do_app/tags>
- CLI, from anywhere with Docker:

    ```bash
    docker pull br4z/to-do_app:0.1.0
    ```

### 4f. Smoke-test the pulled image

To prove the pushed artifact is self-contained, run it using the deploy
compose file (which pulls from the registry instead of building):

```bash
# Wipe the local build so we're forced to pull
docker image rm br4z/to-do_app:local br4z/to-do_app:latest br4z/to-do_app:0.1.0

# Point the deploy compose at our tag
export APP_IMAGE_TAG=0.1.0

# docker-compose.deploy.yml reads env files from /opt/deploy/env/*.env,
# which only exist on the Vagrant VM. For a LOCAL smoke-test we override
# them with our dev .env via a one-off compose command:
docker compose -f docker-compose.yml up -d
# (this rebuilds from source \u2014 that's fine for local verification)
```

> Full local test of `docker-compose.deploy.yml` requires the VM-side
> env files at `/opt/deploy/env/`. That's Step 3 onwards.

### 4g. Log out when done (optional)

```bash
docker logout
```

---

## 5. Clean up

```bash
docker compose down -v
rm -f .env
docker image prune -f
```

Your host is back to baseline (modulo pulled base images in the cache).

---

## Known issues / gotchas

- **`yarn install` fails in the container.** The committed `yarn.lock`
  trips yarn v1.22.22's parser. We use `npm install` in the Dockerfile
  as a workaround. Regenerating the lockfile would fix it but mutates
  the repo.
- **Browserslist warning during tests.** Harmless; `caniuse-lite` is old.
  Ignore.
- **Port 3000 already in use?** Change the left side of `ports:` in
  `docker-compose.yml`, e.g. `"3001:3000"`.
- **MySQL healthcheck slow on first boot.** `start_period: 20s`; if it's
  still unhealthy after 2 minutes, check `docker compose logs mysql`.

# CircleCI setup (Step 5 runbook)

This doc is the one-time account wiring you do OUTSIDE the repo before
the pipeline can actually run.

## 0. Rename default branch `master` -> `main`

Locally (from WSL):

```bash
git branch -m master main
git push -u origin main
```

On GitHub (<https://github.com/LONG-TERM-EFFECTS-OF-SUFFERING/ci_cd_for_a_to-do_app>):

1. Settings -> **Branches** -> Default branch -> switch to `main`.
2. Settings -> Branches -> delete `master` branch protection if any.
3. Back in your shell: `git push origin --delete master`.

Verify:

```bash
git branch --show-current        # main
git remote show origin | grep HEAD   # HEAD branch: main
```

## 1. Sign in to CircleCI

1. Go to <https://app.circleci.com/> -> **Log In with GitHub**.
2. Authorize CircleCI for the `LONG-TERM-EFFECTS-OF-SUFFERING` org (or
   your personal namespace).

## 2. Set up the project

1. In CircleCI UI -> **Projects** -> find `ci_cd_for_a_to-do_app` ->
   **Set Up Project**.
2. When asked how to configure: pick **"Use the .circleci/config.yml
   in my repo"**. Point it at `main`.

> CircleCI will immediately try to run the pipeline. It will FAIL at
> `build_and_push` because we haven't created the Context yet. That's
> expected. The `test` job should pass.

## 3. Create a Docker Hub access token

1. <https://hub.docker.com/> -> Account Settings -> **Security** ->
   **New Access Token**.
2. Description: `circleci-workshop`.
3. Permissions: **Read, Write, Delete** (Delete optional).
4. **Copy the token now** -- Docker Hub only shows it once.

## 4. Create the `docker-hub` Context in CircleCI

Contexts let multiple jobs / projects share secrets without copy-pasting.

1. CircleCI UI -> **Organization Settings** -> **Contexts** ->
   **Create Context**.
2. Name: `docker-hub` (must match exactly -- referenced in config.yml).
3. Add two environment variables:
   - `DOCKERHUB_USERNAME` = `br4z`
   - `DOCKERHUB_TOKEN`    = the token from step 3 (NOT your password)

That's it. The context is now available to any job that declares
`context: - docker-hub` (which `build_and_push` does).

## 5. Re-trigger the pipeline

Easiest way: make any trivial change and push.

```bash
git commit --allow-empty -m "ci: trigger first real pipeline"
git push
```

Expected outcome:

- `test` job: green on every branch.
- `build_and_push` job: green on `main`, skipped on feature branches.
- Result visible on Docker Hub:
  <https://hub.docker.com/r/br4z/to-do_app/tags>
  -- two new tags: `<short-sha>` and `latest`.

## 6. Verify from anywhere

```bash
docker pull br4z/to-do_app:latest
docker run --rm -p 3000:3000 br4z/to-do_app:latest
# ...then in another shell:
curl http://127.0.0.1:3000/items        # should return []
```

## What this pipeline does NOT do yet

- **No deploy.** The `deploy` job will be added in Step 7 and will run
  on the Vagrant VM via a self-hosted runner (Step 6).
- **No notifications** (Slack, email). Optional bonus later.
- **No vulnerability scan** (e.g. Trivy). Optional bonus.

## Common failures

- **build_and_push fails with `unauthorized: incorrect username or password`.**
  Wrong token, or token scope missing Write. Regenerate, update the
  Context value.
- **`Context "docker-hub" not found`.** Context name mismatch, or
  Context was created at the wrong org level.
- **`test` fails on clean repo but passed locally.** Check the Browserslist
  warning -- it's a warning, not a failure. Real issues show as `FAIL`
  lines.
- **Pipeline never triggers.** GitHub webhook missing: Project Settings
  in CircleCI -> **Advanced** -> Stop / Start Building.

## Secrets hygiene reminder

- Token is in a Context, NOT in the repo, NOT in Dockerfile, NOT in
  compose files, NOT in `config.yml`.
- `.env` and `deploy/env/*.env` files are gitignored.
- When you eventually rotate the Docker Hub token (you should, every
  90 days), update the Context value only. No code changes needed.

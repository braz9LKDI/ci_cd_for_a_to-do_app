# deploy/

Future home of deployment-time assets used by CircleCI jobs against the
Vagrant-provisioned Ubuntu VM.

Nothing here is finalized yet. This directory exists so that later steps
have a dedicated, gitignored-friendly place to land.

## Intended contents (later)

- `compose/` — environment-specific overrides for
  `../docker-compose.deploy.yml` (e.g. `docker-compose.prod.yml`).
- `scripts/` — deploy-side shell scripts invoked by CircleCI (pull image,
  render env, `docker compose up -d`, health check, rollback).
- `config/` — templated config files rendered at deploy time.
- `systemd/` — optional unit files if we choose to wrap the compose stack.

## Explicit non-decisions

Do **not** add any of the following until the workshop decides them:

- Final image name / registry / tag strategy.
- Application ports.
- Database engine or credentials.
- Secret storage mechanism.
- Reverse proxy / TLS strategy.

## Related

- VM scaffold: `../infra/vagrant/`
- Compose placeholder: `../docker-compose.deploy.yml`

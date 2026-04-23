# syntax=docker/dockerfile:1.6
#
# Multi-stage Dockerfile for the ToDoApp (Node.js + Express).
#
# Stages:
#   1. deps   -> install ALL dependencies (incl. devDependencies) + build native modules
#   2. test   -> run the Jest test suite against the installed deps
#   3. runtime-> slim image containing only production node_modules + source
#
# The test stage is referenced by CI; local `docker build` will skip it unless
# explicitly targeted with `--target test`.

# -----------------------------------------------------------------------------
# Stage 1: deps
# -----------------------------------------------------------------------------
FROM node:18-alpine AS deps

# sqlite3 is a native module. Alpine needs a toolchain to compile it.
# python3/make/g++ are removed implicitly when this stage is discarded.
RUN apk add --no-cache python3 make g++

WORKDIR /app

# Copy only manifest files first so `npm ci` is cached when source changes
# but dependencies do not.
COPY package.json package-lock.json ./

# `npm install` (not `npm ci`) because the committed package-lock.json is
# out of sync with package.json in this repo (the `resolutions` field is
# yarn-specific). Acceptable for a workshop; switch to `npm ci` after
# regenerating the lockfile with `npm install` locally.
RUN npm install --no-audit --no-fund

# -----------------------------------------------------------------------------
# Stage 2: test
# -----------------------------------------------------------------------------
# Runs the full Jest suite. If tests fail, the image build fails.
# Intended to be targeted explicitly in CI: `docker build --target test .`
FROM deps AS test
WORKDIR /app
COPY . .
ENV NODE_ENV=test
RUN npm test -- --ci --runInBand

# -----------------------------------------------------------------------------
# Stage 3: runtime
# -----------------------------------------------------------------------------
FROM node:18-alpine AS runtime

# Minimal runtime packages:
#   - tini-less: the app already handles SIGTERM (see src/index.js),
#     so we rely on docker's default init behavior enabled at `run` time.
#   - wget: used by HEALTHCHECK.
RUN apk add --no-cache wget

WORKDIR /app

# Copy production-only node_modules by reinstalling with --production.
# This is cheaper than pruning and keeps the layer deterministic.
COPY package.json package-lock.json ./
RUN npm install --omit=dev --no-audit --no-fund \
 && npm cache clean --force

# Copy application source. .dockerignore keeps this small.
COPY src ./src

# The app writes the sqlite DB to /app/data/todo.db by default when
# MYSQL_HOST is not set. In production we use MySQL, but we still
# create the directory so the sqlite fallback works for single-container
# runs. Mount a volume at /app/data to persist across restarts.
RUN mkdir -p /app/data && chown -R node:node /app

# Drop privileges. The `node` user is provided by the official base image.
USER node

EXPOSE 3000

# Healthcheck hits the real route. A 200 proves:
#   - the process is listening
#   - db.init() succeeded (app only starts listening after init)
#   - the /items handler is reachable
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD wget -qO- http://127.0.0.1:3000/items >/dev/null || exit 1

CMD ["node", "src/index.js"]

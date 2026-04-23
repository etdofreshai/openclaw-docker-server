# openclaw-docker-server

This repo gives OpenClaw a persistent-volume runtime instead of baking the OpenClaw install into the image.

The image is intentionally thin:

- base OS + Node + a few utilities
- an idempotent entrypoint
- a `/data` mount that keeps the OpenClaw CLI, home/config, workspace, app caches, and bootstrap markers

That means container restarts are fast, first boot can perform installation and setup, and later boots skip work that is already complete.

## Flow

When `openclaw-server` starts, the entrypoint does three phases:

1. `install`

- Installs `${OPENCLAW_NPM_SPEC}` into `/data/openclaw`
- Skips if `/data/openclaw/bin/openclaw` already exists and the requested npm spec has not changed

2. `setup-once`

- Runs `OPENCLAW_SETUP_CMD` once if provided
- Skips once `/data/state/setup-complete` exists

3. `run`

- Starts OpenClaw gateway by default
- Can switch to a long-lived shell container or a custom command
- Watches gateway health and locally restarts it if it stays down for 5 minutes

## Persistent layout

Everything below lives in the `/data` mount you provide in Dokploy:

- `/data/openclaw`: npm global prefix containing the OpenClaw CLI install
- `/data/home/.openclaw`: OpenClaw home, config, sessions, installed apps/skills, and workspace data
- `/data/apps`: extra app caches such as Playwright browsers
- `/data/state`: install/setup markers and requested npm spec

## Quick start

```bash
docker compose up -d --build
docker compose logs -f openclaw-server
```

For Dokploy, mount your persistent storage at `/data` and set runtime environment there. On first boot, the container installs OpenClaw into that mount. On later boots, it reuses that install.

## First-time OpenClaw setup

The container bootstrap is automatic, but OpenClaw onboarding is still your call because it is usually interactive and environment-specific.

Run it once against the persisted volume:

```bash
docker compose exec openclaw-server /data/openclaw/bin/openclaw onboard
```

If you want the container to just stay alive as an OS-like runtime while you exec in manually, set:

```env
OPENCLAW_RUN_MODE=shell
```

Then use:

```bash
docker compose exec openclaw-server bash
```

## Useful commands

```bash
docker compose ps
docker compose logs -f openclaw-server
docker compose exec openclaw-server bash
docker compose exec openclaw-server /data/openclaw/bin/openclaw --version
```

## Current design choices

- OpenClaw is installed via `npm install -g` into a persistent prefix instead of being baked into the image.
- The default run mode is `gateway` so the container is useful immediately.
- A `shell` mode is available if you want a pure always-running host container.
- OS packages still belong in the image. Persistence is aimed at OpenClaw itself, OpenClaw state, and user-installed runtime data under `/data`.
- The gateway watchdog uses the local `/healthz` endpoint instead of tracking one PID, so OpenClaw can respawn internally without being treated as down.

## Research notes

This repo shape is based on the current official OpenClaw install and Docker guidance:

- The install docs recommend `npm install -g openclaw@latest` or `openclaw onboard --install-daemon` for standard installs.
- The installer internals docs describe non-interactive automation paths and a local-prefix installer for automation.
- The Docker docs recommend persisting OpenClaw home data and show the gateway running inside Docker with `/home/node/.openclaw` mounted.

Official references:

- [Install docs](https://docs.openclaw.ai/install/index)
- [Installer internals](https://docs.openclaw.ai/install/installer)
- [Docker docs](https://docs.openclaw.ai/install/docker)

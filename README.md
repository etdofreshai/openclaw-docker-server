# openclaw-docker-server

Docker Compose setup for running the official OpenClaw container with persistent storage.

The base compose file uses:

- `ghcr.io/openclaw/openclaw:latest`
- OpenClaw gateway bind mode `lan`
- an authenticated healthcheck that reads the generated gateway token from the persisted config

## Quick Start

```bash
docker compose up -d
docker compose logs -f openclaw-server
```

The base [docker-compose.yml](C:/Users/etgarcia/code/workspace/repos/openclaw-docker-server/docker-compose.yml) does not publish ports. That keeps it deployment-friendly for Dokploy/Traefik-style routing.

## Local Run

Use the local override to publish the gateway on host port `18791`, avoiding a local or WSL OpenClaw server already using `18789`.

```powershell
docker compose -f docker-compose.yml -f docker-compose-local.yml up -d
```

Open:

```text
http://127.0.0.1:18791/
```

The local override reuses the named Docker volume:

```text
openclaw-docker-server_openclaw-local-data
```

The volume mount is intentionally local-only. Dokploy or another deployment target should provide its own persistent storage for `/home/node`.

## First-Time Config

If the gateway starts without config, initialize it once against the persisted volume:

```powershell
docker compose -f docker-compose.yml -f docker-compose-local.yml stop openclaw-server
docker compose -f docker-compose.yml -f docker-compose-local.yml run --rm --no-deps --user root --entrypoint sh openclaw-server -lc "mkdir -p /home/node/.openclaw && chown -R node:node /home/node"
docker compose -f docker-compose.yml -f docker-compose-local.yml run --rm --no-deps --entrypoint node openclaw-server dist/index.js config set gateway.mode local
docker compose -f docker-compose.yml -f docker-compose-local.yml run --rm --no-deps --entrypoint node openclaw-server dist/index.js config set gateway.bind lan
docker compose -f docker-compose.yml -f docker-compose-local.yml run --rm --no-deps --entrypoint node openclaw-server dist/index.js config set gateway.port 18789 --strict-json
docker compose -f docker-compose.yml -f docker-compose-local.yml up -d
```

To print the dashboard URL without opening a browser:

```powershell
docker compose -f docker-compose.yml -f docker-compose-local.yml exec openclaw-server node dist/index.js dashboard --no-open
```

## Useful Commands

```bash
docker compose ps
docker compose logs -f openclaw-server
docker compose exec openclaw-server bash
docker compose exec openclaw-server node dist/index.js health --token "<token>"
```

## Notes

- Use bind mode values such as `lan`, `loopback`, `tailnet`, `auto`, or `custom`, not raw hosts like `0.0.0.0`.
- OpenClaw stores config, auth, workspace data, sessions, and installed runtime state under `/home/node/.openclaw`.
- The official Docker docs describe the GHCR image and `/home/node` persistence model.

Official reference:

- [OpenClaw Docker docs](https://docs.openclaw.ai/install/docker)

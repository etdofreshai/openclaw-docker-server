FROM node:24-bookworm

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
  bash \
  ca-certificates \
  curl \
  git \
  jq \
  procps \
  tini \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/openclaw-server

COPY docker/entrypoint.sh /opt/openclaw-server/docker/entrypoint.sh
RUN chmod +x /opt/openclaw-server/docker/entrypoint.sh

ENV OPENCLAW_DATA_DIR=/data \
    OPENCLAW_PREFIX_DIR=/data/openclaw \
    OPENCLAW_HOME_DIR=/data/home \
    OPENCLAW_STATE_DIR=/data/state \
    OPENCLAW_HOOKS_DIR=/data/hooks \
    OPENCLAW_NPM_SPEC=openclaw@latest \
    OPENCLAW_RUN_MODE=gateway \
    OPENCLAW_GATEWAY_BIND=0.0.0.0 \
    OPENCLAW_GATEWAY_PORT=18789 \
    OPENCLAW_BRIDGE_PORT=18790 \
    PLAYWRIGHT_BROWSERS_PATH=/data/apps/playwright

ENTRYPOINT ["/usr/bin/tini", "--", "/opt/openclaw-server/docker/entrypoint.sh"]

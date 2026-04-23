#!/usr/bin/env bash

set -Eeuo pipefail

timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

log() {
  printf '[%s] %s\n' "$(timestamp)" "$*"
}

require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || {
    log "Required command not found: $cmd"
    exit 1
  }
}

run_hook_dir() {
  local dir="$1"
  local label="$2"
  if [[ ! -d "$dir" ]]; then
    return 0
  fi

  local hook
  while IFS= read -r hook; do
    [[ -z "$hook" ]] && continue
    log "Running ${label} hook: $hook"
    if [[ "$hook" == *.sh ]]; then
      bash "$hook"
    elif [[ -x "$hook" ]]; then
      "$hook"
    else
      log "Skipping non-executable hook: $hook"
    fi
  done < <(find "$dir" -maxdepth 1 -type f | sort)
}

is_gateway_healthy() {
  node -e "fetch('http://127.0.0.1:' + (process.env.OPENCLAW_GATEWAY_PORT || '18789') + '/healthz').then((r)=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))" >/dev/null 2>&1
}

ensure_dirs() {
  mkdir -p \
    "$OPENCLAW_DATA_DIR" \
    "$OPENCLAW_PREFIX_DIR" \
    "$OPENCLAW_HOME_DIR" \
    "$OPENCLAW_STATE_DIR" \
    "$OPENCLAW_HOOKS_DIR/install.d" \
    "$OPENCLAW_HOOKS_DIR/setup-once.d" \
    "$OPENCLAW_HOOKS_DIR/run.d" \
    "$OPENCLAW_APPS_DIR" \
    "$OPENCLAW_HOME"

  touch "$BOOT_LOG_FILE"
}

install_openclaw() {
  local install_marker="$OPENCLAW_STATE_DIR/install-complete"
  local spec_file="$OPENCLAW_STATE_DIR/openclaw-npm-spec"
  local current_spec=""
  local desired_spec="$OPENCLAW_NPM_SPEC"

  if [[ -f "$spec_file" ]]; then
    current_spec="$(<"$spec_file")"
  fi

  if [[ "${OPENCLAW_FORCE_INSTALL:-0}" != "1" ]] \
    && [[ -x "$OPENCLAW_BIN" ]] \
    && [[ -f "$install_marker" ]] \
    && [[ "$current_spec" == "$desired_spec" ]]; then
    log "Install phase already complete for $desired_spec"
    return 0
  fi

  run_hook_dir "$OPENCLAW_HOOKS_DIR/install.d" "install"

  require_cmd npm
  log "Installing $desired_spec into $OPENCLAW_PREFIX_DIR"
  npm install -g "$desired_spec"

  printf '%s\n' "$desired_spec" >"$spec_file"
  touch "$install_marker"
  log "Install phase complete"
}

setup_once() {
  local setup_marker="$OPENCLAW_STATE_DIR/setup-complete"

  if [[ "${OPENCLAW_FORCE_SETUP:-0}" != "1" ]] && [[ -f "$setup_marker" ]]; then
    log "Setup phase already complete"
    return 0
  fi

  if [[ -n "${OPENCLAW_SETUP_CMD:-}" ]]; then
    log "Running OPENCLAW_SETUP_CMD"
    bash -lc "$OPENCLAW_SETUP_CMD"
  fi

  run_hook_dir "$OPENCLAW_HOOKS_DIR/setup-once.d" "setup-once"

  touch "$setup_marker"
  log "Setup phase complete"
}

run_gateway_once() {
  run_hook_dir "$OPENCLAW_HOOKS_DIR/run.d" "run"

  log "Starting OpenClaw gateway on ${OPENCLAW_GATEWAY_BIND}:${OPENCLAW_GATEWAY_PORT}"
  "$OPENCLAW_BIN" gateway \
    --bind "$OPENCLAW_GATEWAY_BIND" \
    --port "$OPENCLAW_GATEWAY_PORT" &
  local child_pid=$!
  wait "$child_pid"
  local exit_code=$?
  return "$exit_code"
}

watch_gateway() {
  local down_since=""
  local exit_code=0

  while true; do
    if is_gateway_healthy; then
      sleep "$OPENCLAW_WATCHDOG_INTERVAL_SECONDS"
      continue
    fi

    if [[ -z "$down_since" ]]; then
      down_since="$(date +%s)"
      log "OpenClaw is down; starting ${OPENCLAW_WATCHDOG_GRACE_SECONDS}s watchdog window"
    fi

    local now
    now="$(date +%s)"
    if (( now - down_since < OPENCLAW_WATCHDOG_GRACE_SECONDS )); then
      sleep "$OPENCLAW_WATCHDOG_INTERVAL_SECONDS"
      continue
    fi

    log "OpenClaw has been down for ${OPENCLAW_WATCHDOG_GRACE_SECONDS}s; restarting locally"
    down_since=""
    run_gateway_once || exit_code=$?
    log "OpenClaw gateway exited with code $exit_code"
    sleep "$OPENCLAW_WATCHDOG_INTERVAL_SECONDS"
  done
}

run_mode() {
  local exit_code=0

  case "${OPENCLAW_RUN_MODE:-gateway}" in
    gateway)
      run_gateway_once || exit_code=$?
      log "OpenClaw gateway exited with code $exit_code"
      watch_gateway
      ;;
    shell)
      log "Starting interactive shell loop"
      exec bash -lc 'while true; do sleep 3600; done'
      ;;
    custom)
      if [[ -z "${OPENCLAW_RUN_CMD:-}" ]]; then
        log "OPENCLAW_RUN_MODE=custom requires OPENCLAW_RUN_CMD"
        exit 1
      fi
      log "Starting custom command"
      exec bash -lc "$OPENCLAW_RUN_CMD"
      ;;
    *)
      log "Unknown OPENCLAW_RUN_MODE: ${OPENCLAW_RUN_MODE:-}"
      exit 1
      ;;
  esac
}

export OPENCLAW_DATA_DIR="${OPENCLAW_DATA_DIR:-/data}"
export OPENCLAW_PREFIX_DIR="${OPENCLAW_PREFIX_DIR:-$OPENCLAW_DATA_DIR/openclaw}"
export OPENCLAW_HOME_DIR="${OPENCLAW_HOME_DIR:-$OPENCLAW_DATA_DIR/home}"
export OPENCLAW_STATE_DIR="${OPENCLAW_STATE_DIR:-$OPENCLAW_DATA_DIR/state}"
export OPENCLAW_HOOKS_DIR="${OPENCLAW_HOOKS_DIR:-$OPENCLAW_DATA_DIR/hooks}"
export OPENCLAW_APPS_DIR="${OPENCLAW_APPS_DIR:-$OPENCLAW_DATA_DIR/apps}"
export HOME="${OPENCLAW_HOME_DIR}"
export OPENCLAW_HOME="${OPENCLAW_HOME:-$OPENCLAW_HOME_DIR/.openclaw}"
export OPENCLAW_BIN="${OPENCLAW_PREFIX_DIR}/bin/openclaw"
export PATH="${OPENCLAW_PREFIX_DIR}/bin:${PATH}"
export NPM_CONFIG_PREFIX="${OPENCLAW_PREFIX_DIR}"
export BOOT_LOG_FILE="${OPENCLAW_STATE_DIR}/last-boot.log"
export OPENCLAW_WATCHDOG_GRACE_SECONDS="${OPENCLAW_WATCHDOG_GRACE_SECONDS:-300}"
export OPENCLAW_WATCHDOG_INTERVAL_SECONDS="${OPENCLAW_WATCHDOG_INTERVAL_SECONDS:-5}"

ensure_dirs
exec > >(tee -a "$BOOT_LOG_FILE") 2>&1
log "Bootstrapping OpenClaw server"
install_openclaw
setup_once
run_mode

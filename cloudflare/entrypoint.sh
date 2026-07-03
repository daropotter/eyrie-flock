#!/usr/bin/env bash
# Cloudflare Containers entrypoint.
#
# CF container disk is EPHEMERAL — it is wiped on every restart/sleep/redeploy.
# To keep opencode's config, API keys and sessions, we mirror them to R2:
#   * on boot           -> restore from R2 into the local dirs
#   * every SYNC_INTERVAL seconds -> push local changes to R2
#   * on SIGTERM (sleep/redeploy) -> final push before shutdown
#
# Only one instance runs (max_instances: 1 + a single "main" name), so there is
# a single writer and no sync conflicts.

set -uo pipefail

CONFIG_DIR="/home/opencode/.config/opencode"
DATA_DIR="/home/opencode/.local/share/opencode"
SYNC_INTERVAL="${SYNC_INTERVAL:-60}"

# rclone remote "r2:" configured entirely via env vars.
export RCLONE_CONFIG_R2_TYPE=s3
export RCLONE_CONFIG_R2_PROVIDER=Cloudflare
export RCLONE_CONFIG_R2_ENV_AUTH=false
export RCLONE_CONFIG_R2_ACCESS_KEY_ID="${R2_ACCESS_KEY_ID:-}"
export RCLONE_CONFIG_R2_SECRET_ACCESS_KEY="${R2_SECRET_ACCESS_KEY:-}"
export RCLONE_CONFIG_R2_ENDPOINT="${R2_ENDPOINT:-}"
export RCLONE_CONFIG_R2_ACL=private
# R2 does not support multipart ETag validation the S3 way; keep uploads simple.
RCLONE_FLAGS="--transfers=8 --checkers=8 --s3-no-check-bucket --s3-upload-cutoff=5G"

r2_enabled() {
    [ -n "${R2_BUCKET:-}" ] && [ -n "${R2_ACCESS_KEY_ID:-}" ] && [ -n "${R2_ENDPOINT:-}" ]
}

restore() {
    if ! r2_enabled; then
        echo "[entrypoint] R2 not configured — running with ephemeral state."
        return
    fi
    echo "[entrypoint] Restoring state from R2 (r2:${R2_BUCKET})..."
    # shellcheck disable=SC2086
    rclone copy "r2:${R2_BUCKET}/config" "$CONFIG_DIR" $RCLONE_FLAGS 2>&1 | sed 's/^/[rclone] /' || true
    # shellcheck disable=SC2086
    rclone copy "r2:${R2_BUCKET}/data" "$DATA_DIR" $RCLONE_FLAGS 2>&1 | sed 's/^/[rclone] /' || true
}

push() {
    r2_enabled || return 0
    # shellcheck disable=SC2086
    rclone sync "$CONFIG_DIR" "r2:${R2_BUCKET}/config" $RCLONE_FLAGS 2>/dev/null || true
    # shellcheck disable=SC2086
    rclone sync "$DATA_DIR" "r2:${R2_BUCKET}/data" $RCLONE_FLAGS 2>/dev/null || true
}

restore

# Periodic background sync.
(
    while true; do
        sleep "$SYNC_INTERVAL"
        push
    done
) &
SYNC_PID=$!

# Start the opencode server (serves API + web UI at /).
opencode serve --hostname 0.0.0.0 --port 4096 &
OC_PID=$!

shutdown() {
    echo "[entrypoint] SIGTERM — final sync to R2..."
    kill "$SYNC_PID" 2>/dev/null || true
    push
    echo "[entrypoint] Sync done, stopping opencode."
    kill -TERM "$OC_PID" 2>/dev/null || true
    wait "$OC_PID" 2>/dev/null || true
    exit 0
}
trap shutdown TERM INT

wait "$OC_PID"

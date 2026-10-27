#!/usr/bin/env bash
# Runs ON THE SERVER. The GitHub Actions workflow streams this file over SSH
# (ssh user@host 'bash -s'), so nothing needs to be copied to the server first.
#
# Steps: pull new image -> replace container -> wait until healthy
#        -> if unhealthy, roll back to the previous image and exit 1.
set -euo pipefail

: "${IMAGE:?IMAGE is required (e.g. ghcr.io/user/repo:sha)}"
APP_NAME="${APP_NAME:-cicd-demo}"
HOST_PORT="${HOST_PORT:-8080}"
CONTAINER_PORT=3000
HEALTH_TIMEOUT="${HEALTH_TIMEOUT:-60}"

log() { echo "[deploy] $*"; }

# 1. Log in to GHCR (token is short-lived, issued by GitHub for this workflow run)
if [[ -n "${GHCR_TOKEN:-}" ]]; then
  echo "$GHCR_TOKEN" | docker login ghcr.io -u "${GHCR_USER:?GHCR_USER is required}" --password-stdin
fi

# 2. Remember what is running now, so we can roll back to it
PREV_IMAGE="$(docker inspect -f '{{.Config.Image}}' "$APP_NAME" 2>/dev/null || true)"
log "Previous image: ${PREV_IMAGE:-none}"
log "New image:      $IMAGE"

start_container() {
  docker run -d \
    --name "$APP_NAME" \
    --restart unless-stopped \
    -p "${HOST_PORT}:${CONTAINER_PORT}" \
    "$1" > /dev/null
}

# Returns 0 when healthy, 1 when it crashed, restarted, turned unhealthy or timed out
wait_healthy() {
  local waited=0 status restarts state
  while (( waited < HEALTH_TIMEOUT )); do
    status="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$APP_NAME" 2>/dev/null || echo missing)"
    restarts="$(docker inspect -f '{{.RestartCount}}' "$APP_NAME" 2>/dev/null || echo 0)"
    state="$(docker inspect -f '{{.State.Status}}' "$APP_NAME" 2>/dev/null || echo missing)"
    if [[ "$status" == "healthy" ]]; then return 0; fi
    if [[ "$status" == "unhealthy" || "$state" == "exited" || "$state" == "restarting" || "$state" == "missing" || "$restarts" -gt 0 ]]; then
      return 1
    fi
    sleep 2
    waited=$((waited + 2))
  done
  return 1
}

# 3. Pull first, so the swap below is as short as possible
docker pull "$IMAGE"

# 4. Replace the running container
if docker inspect "$APP_NAME" > /dev/null 2>&1; then
  docker stop "$APP_NAME" > /dev/null || true
  docker rm "$APP_NAME" > /dev/null
fi
start_container "$IMAGE"

# 5. Success path
if wait_healthy; then
  log "Deployment healthy: $IMAGE"
  docker image prune -f > /dev/null || true   # removes only dangling layers
  exit 0
fi

# 6. Failure path: show logs, roll back
log "ERROR: new version did not become healthy. Last container logs:"
docker logs --tail 50 "$APP_NAME" || true
docker rm -f "$APP_NAME" > /dev/null || true

if [[ -n "$PREV_IMAGE" ]]; then
  log "Rolling back to $PREV_IMAGE"
  start_container "$PREV_IMAGE"
  if wait_healthy; then
    log "Rollback successful. The old version is running again."
  else
    log "CRITICAL: rollback also failed. Manual action needed."
  fi
else
  log "No previous version to roll back to."
fi
exit 1

#!/usr/bin/env bash
# scripts/post-deploy-monitor.sh
# Monitors the active environment after a traffic switch.
# Calls rollback.sh automatically if thresholds are breached.
#
# Usage: bash post-deploy-monitor.sh [confidence_window_seconds]
# Default confidence window: 120 seconds (2 minutes)

set -euo pipefail

CONFIDENCE_WINDOW="${1:-120}"
POLL_INTERVAL=5          # Seconds between health checks
MAX_CONSECUTIVE_FAILURES=3
MAX_ERRORS_PER_WINDOW=2
LATENCY_THRESHOLD=2.0    # Seconds: responses slower than this count as slow
SLOW_THRESHOLD_COUNT=3   # How many slow responses in 5 polls trigger rollback

ACTIVE_ENV_STATE="/opt/kijanikiosk/.active-env"
PROXY_HEALTH_URL="http://127.0.0.1:80/health"
SCRIPTS_DIR="$(dirname "$0")"

log()      { echo "[$(date -u +%H:%M:%S)] [MONITOR] $*"; }
log_warn() { echo "[$(date -u +%H:%M:%S)] [MONITOR WARN] $*"; }
log_fail() { echo "[$(date -u +%H:%M:%S)] [MONITOR FAIL] $*" >&2; }

trigger_rollback() {
  local reason="$1"
  log_fail "ROLLBACK TRIGGERED: ${reason}"
  log_fail "Calling rollback.sh..."
  bash "${SCRIPTS_DIR}/rollback.sh"
  local rb_exit=$?
  if [ ${rb_exit} -eq 0 ]; then
    log "Rollback completed successfully."
  else
    log_fail "Rollback script exited with code ${rb_exit}. Manual intervention required."
  fi
  exit 1
}

main() {
  local active_env
  active_env=$(cat "${ACTIVE_ENV_STATE}" 2>/dev/null || echo "unknown")
  log "=== Post-deployment monitoring: ${active_env} environment ==="
  log "Confidence window: ${CONFIDENCE_WINDOW}s | Poll interval: ${POLL_INTERVAL}s"

  local elapsed=0
  local consecutive_failures=0
  local errors_in_window=0
  local slow_in_last_five=0
  local poll_count=0

  while [ ${elapsed} -lt ${CONFIDENCE_WINDOW} ]; do
    poll_count=$((poll_count + 1))
    local http_code response_time

    # Poll the health endpoint, capture HTTP status and response time
    http_code=$(curl -sf --max-time 5 \
      --write-out "%{http_code}" \
      --output /dev/null \
      "${PROXY_HEALTH_URL}" 2>/dev/null) || http_code="000"

    response_time=$(curl -sf --max-time 5 \
      --write-out "%{time_total}" \
      --output /dev/null \
      "${PROXY_HEALTH_URL}" 2>/dev/null) || response_time="0"

    log "Poll ${poll_count}: HTTP ${http_code} | ${response_time}s | elapsed: ${elapsed}s"

    # Check availability
    if [ "${http_code}" = "000" ] || [ "${http_code:0:1}" != "2" ]; then
      consecutive_failures=$((consecutive_failures + 1))
      errors_in_window=$((errors_in_window + 1))
      log_warn "Health check failed (consecutive: ${consecutive_failures}, window errors: ${errors_in_window})"
    else
      consecutive_failures=0
    fi

    # Check latency (bash cannot do float comparison; use awk)
    if echo "${response_time}" | awk -v thresh="${LATENCY_THRESHOLD}" \
        '{ exit ($1 > thresh) ? 0 : 1 }'; then
      slow_in_last_five=$((slow_in_last_five + 1))
      log_warn "Slow response: ${response_time}s (slow count in last 5: ${slow_in_last_five})"
    else
      # Decay the slow counter (only track last 5 polls)
      [ ${slow_in_last_five} -gt 0 ] && slow_in_last_five=$((slow_in_last_five - 1))
    fi

    # Reset window error counter every 10 polls
    [ $((poll_count % 10)) -eq 0 ] && errors_in_window=0

    # Evaluate rollback conditions
    [ ${consecutive_failures} -ge ${MAX_CONSECUTIVE_FAILURES} ] && \
      trigger_rollback "${consecutive_failures} consecutive health check failures"

    [ ${errors_in_window} -gt ${MAX_ERRORS_PER_WINDOW} ] && \
      trigger_rollback "error rate exceeded: ${errors_in_window} errors in window"

    [ ${slow_in_last_five} -ge ${SLOW_THRESHOLD_COUNT} ] && \
      trigger_rollback "latency threshold exceeded: ${slow_in_last_five} slow responses in last 5 polls"

    sleep ${POLL_INTERVAL}
    elapsed=$((elapsed + POLL_INTERVAL))
  done

  log "=== Confidence window passed: ${active_env} deployment declared healthy ==="
  exit 0
}

main "$@"
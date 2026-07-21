#!/bin/bash
#
# Lightweight health check for the Boardgame deployment.
# Designed for a resource-constrained K3s node where a full monitoring
# stack (Prometheus/Grafana) isn't viable - see docs/future-improvements.md
# for the resource analysis behind this decision.
#
# Run via cron on the EC2 node; logs to a local file for later review.
# Intentionally simple: a real HTTP check (not just pod status) plus
# resource snapshot, appended as a single timestamped line - cheap to
# run, cheap to read, cheap to grep.

set -euo pipefail

LOG_FILE="/home/ubuntu/boardgame-healthcheck.log"
APP_URL="http://localhost:30080"
TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

# HTTP check - the real test of whether the app is actually serving,
# not just whether Kubernetes thinks the pod is "Running"
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$APP_URL" || echo "000")

# Pod status, straight from Kubernetes
POD_STATUS=$(kubectl get pods -l app=boardgame -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "UNKNOWN")
POD_READY=$(kubectl get pods -l app=boardgame -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null || echo "unknown")
RESTART_COUNT=$(kubectl get pods -l app=boardgame -o jsonpath='{.items[0].status.containerStatuses[0].restartCount}' 2>/dev/null || echo "?")

# Resource usage snapshot (requires metrics-server, already running)
POD_MEM=$(kubectl top pods -l app=boardgame --no-headers 2>/dev/null | awk '{print $3}' || echo "?")
NODE_MEM_PCT=$(kubectl top nodes --no-headers 2>/dev/null | awk '{print $5}' || echo "?")

# Simple pass/fail verdict
if [ "$HTTP_STATUS" == "200" ] && [ "$POD_READY" == "true" ]; then
    STATUS="OK"
else
    STATUS="ALERT"
fi

echo "${TIMESTAMP} status=${STATUS} http=${HTTP_STATUS} pod_phase=${POD_STATUS} ready=${POD_READY} restarts=${RESTART_COUNT} pod_mem=${POD_MEM} node_mem_pct=${NODE_MEM_PCT}" >> "$LOG_FILE"

# Non-zero exit on ALERT so cron's own failure detection (mail, logging) can pick it up too
if [ "$STATUS" == "ALERT" ]; then
    exit 1
fi

#!/usr/bin/env bash
set -euo pipefail

# proxy.sh — Launch a throwaway GCP VM as an Exit Proxy in a region, open an SSH
# SOCKS5 tunnel to it, and delete the VM when you quit.
#
# Usage:   ./proxy.sh <region>      # known: tw, jp, us
#
# Flip the "Region Proxy Switcher" extension ON while running. Ctrl-C to stop:
# the tunnel closes and the VM is deleted.
#
# ACCEPTED RISK: teardown relies on a clean exit. On power loss or kill -9 the
# trap won't fire and the VM keeps billing until you delete it manually:
#     gcloud compute instances delete proxy-<region> --zone <zone>

# ---- locate gcloud -------------------------------------------------------
GCLOUD="${GCLOUD:-gcloud}"
if ! command -v "$GCLOUD" >/dev/null 2>&1; then
  for c in \
    "$HOME/Workspace/google-cloud-sdk/bin/gcloud" \
    "$HOME/google-cloud-sdk/bin/gcloud"; do
    [ -x "$c" ] && GCLOUD="$c" && break
  done
fi
command -v "$GCLOUD" >/dev/null 2>&1 || { echo "ERROR: gcloud not found"; exit 1; }

# ---- config (override any of these via env vars) -------------------------
REGION="${1:-}"
[ -n "$REGION" ] || { echo "ERROR: region required (known: tw, jp, us)"; echo "Usage: ./proxy.sh <region>"; exit 1; }
case "$REGION" in
  tw|taiwan) ZONE="asia-east1-b" ;;        # Changhua, Taiwan
  jp|japan)  ZONE="asia-northeast1-b" ;;   # Tokyo, Japan
  us|usa)    ZONE="us-central1-a" ;;        # Iowa, USA
  *) echo "ERROR: unknown region '$REGION' (known: tw, jp, us)"; exit 1 ;;
esac

PROJECT="${PROJECT:-$("$GCLOUD" config get-value project 2>/dev/null)}"
INSTANCE_NAME="${INSTANCE_NAME:-proxy-$REGION}"
MACHINE_TYPE="${MACHINE_TYPE:-e2-micro}"
IMAGE_FAMILY="${IMAGE_FAMILY:-debian-12}"
IMAGE_PROJECT="${IMAGE_PROJECT:-debian-cloud}"
LOCAL_PORT="${LOCAL_PORT:-1080}"

[ -n "$PROJECT" ] || { echo "ERROR: no GCP project set (gcloud config set project ...)"; exit 1; }

echo "Project : $PROJECT"
echo "Region  : $REGION  ->  zone $ZONE"
echo "Instance: $INSTANCE_NAME ($MACHINE_TYPE)"
echo "Tunnel  : SOCKS5 127.0.0.1:$LOCAL_PORT"
echo

gc() { "$GCLOUD" --project="$PROJECT" "$@"; }

# ---- teardown ------------------------------------------------------------
CLEANED=0
cleanup() {
  [ "$CLEANED" -eq 1 ] && return
  CLEANED=1
  echo
  echo ">> Deleting VM $INSTANCE_NAME ..."
  if gc compute instances delete "$INSTANCE_NAME" --zone="$ZONE" --quiet >/dev/null 2>&1; then
    echo ">> Deleted."
  else
    echo ">> WARNING: delete may have failed — check the list below."
  fi

  # List any live VMs so you can confirm nothing is left billing.
  echo ">> Live VMs still in project $PROJECT:"
  if gc compute instances list >/dev/null 2>&1; then
    live=$(gc compute instances list 2>/dev/null)
    if [ -z "$live" ]; then
      echo "   (none) — nothing is billing now."
    else
      echo "$live" | sed 's/^/   /'
      echo ">> WARNING: VM(s) above are still running. Delete with:"
      echo "   $GCLOUD compute instances delete <NAME> --zone=<ZONE>"
    fi
  else
    echo "   (could not list — verify manually: $GCLOUD compute instances list)"
  fi
}
trap cleanup EXIT INT TERM

# ---- launch --------------------------------------------------------------
# Clear any leftover instance from an unclean exit so create succeeds.
if gc compute instances describe "$INSTANCE_NAME" --zone="$ZONE" >/dev/null 2>&1; then
  echo ">> Found a leftover instance, deleting it first ..."
  gc compute instances delete "$INSTANCE_NAME" --zone="$ZONE" --quiet >/dev/null 2>&1 || true
fi

echo ">> Creating VM ..."
# --no-service-account/--no-scopes: box only accepts SSH, never calls GCP APIs,
# so it carries no credentials.
gc compute instances create "$INSTANCE_NAME" \
  --zone="$ZONE" \
  --machine-type="$MACHINE_TYPE" \
  --image-family="$IMAGE_FAMILY" \
  --image-project="$IMAGE_PROJECT" \
  --no-service-account --no-scopes >/dev/null

echo ">> Waiting for SSH to come up ..."
ready=0
for _ in $(seq 1 30); do
  if gc compute ssh "$INSTANCE_NAME" --zone="$ZONE" \
       --ssh-flag="-o StrictHostKeyChecking=accept-new" \
       --ssh-flag="-o ConnectTimeout=10" \
       --command="true" >/dev/null 2>&1; then
    ready=1; break
  fi
  sleep 5
done
[ "$ready" -eq 1 ] || { echo "ERROR: SSH never came up"; exit 1; }

EXIT_IP=$(gc compute ssh "$INSTANCE_NAME" --zone="$ZONE" \
  --ssh-flag="-o StrictHostKeyChecking=accept-new" \
  --command="curl -s --max-time 10 ifconfig.me || echo '?'" 2>/dev/null || echo '?')
echo ">> Exit IP: $EXIT_IP"

echo
echo "=========================================================="
echo "  Proxy READY.  Turn the Chrome extension ON."
echo "  Press Ctrl-C here to disconnect AND delete the VM."
echo "=========================================================="
echo

# SOCKS5 tunnel; -N = forward only, no shell. Background + wait so the trap
# fires promptly on Ctrl-C.
gc compute ssh "$INSTANCE_NAME" --zone="$ZONE" \
  --ssh-flag="-N" \
  --ssh-flag="-D ${LOCAL_PORT}" \
  --ssh-flag="-o StrictHostKeyChecking=accept-new" \
  --ssh-flag="-o ServerAliveInterval=30" \
  --ssh-flag="-o ExitOnForwardFailure=yes" &
SSH_PID=$!
wait "$SSH_PID"

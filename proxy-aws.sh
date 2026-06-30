#!/usr/bin/env bash
set -euo pipefail

# proxy-aws.sh — AWS backend twin of proxy.sh. Launch a throwaway EC2 instance as
# an Exit Proxy in a region, open an SSH SOCKS5 tunnel to it, and tear it all down
# when you quit. Same UX and same local SOCKS port as proxy.sh, so the Chrome
# extension works unchanged.
#
# Usage:   ./proxy-aws.sh <region>      # known: tw, jp, us
#
# SECURITY (locked-down): inbound SSH is restricted to YOUR current public IP /32
# via a dedicated, per-session security group. The box carries no AWS credentials
# (no IAM instance profile) and requires IMDSv2.
#
# Auth uses an ephemeral key pair: a per-session ed25519 key is generated locally,
# its PUBLIC half is imported via `ec2 import-key-pair` (the private key never
# touches the AWS API), and the instance launches with --key-name. Teardown
# deletes the key pair. See docs/adr/0003 for why this is used over SSM/EIC (the
# only available IAM identity is denied ssm:*, iam:PassRole, and EIC's
# SendSSHPublicKey — so the AWS-native zero-inbound paths are not callable).
#
# ACCEPTED RISK: teardown relies on a clean exit. On power loss or kill -9 the trap
# won't fire and the instance keeps billing until you delete it manually. The
# teardown also lists anything left behind so you can clean up.

export AWS_PAGER=""   # never drop into the interactive pager

# ---- locate aws ----------------------------------------------------------
AWS="${AWS:-aws}"
if ! command -v "$AWS" >/dev/null 2>&1; then
  for c in /usr/local/bin/aws /opt/homebrew/bin/aws; do
    [ -x "$c" ] && AWS="$c" && break
  done
fi
command -v "$AWS" >/dev/null 2>&1 || { echo "ERROR: aws CLI not found"; exit 1; }

# ---- config (override any of these via env vars) -------------------------
REGION_ARG="${1:-}"
[ -n "$REGION_ARG" ] || { echo "ERROR: region required (known: tw, jp, us)"; echo "Usage: ./proxy-aws.sh <region>"; exit 1; }
case "$REGION_ARG" in
  tw|taiwan) AWS_REGION="ap-east-2" ;;        # Taipei, Taiwan
  jp|japan)  AWS_REGION="ap-northeast-1" ;;   # Tokyo, Japan
  us|usa)    AWS_REGION="us-east-1" ;;         # N. Virginia, USA
  *) echo "ERROR: unknown region '$REGION_ARG' (known: tw, jp, us)"; exit 1 ;;
esac

INSTANCE_TYPE="${INSTANCE_TYPE:-t4g.micro}"   # arm64; pair with an arm64 AMI
INSTANCE_NAME="${INSTANCE_NAME:-proxy-$REGION_ARG}"
SG_NAME="${SG_NAME:-rps-proxy-$REGION_ARG}"
KEY_NAME="${KEY_NAME:-rps-proxy-$REGION_ARG}"   # name of the imported EC2 key pair
LOCAL_PORT="${LOCAL_PORT:-1080}"
SSH_USER="${SSH_USER:-ec2-user}"              # default user on Amazon Linux 2023

# `command` bypasses this very function so we call the real aws binary, not
# recurse. Without it, when $AWS is the bare name "aws" (the case when aws is
# already on PATH), "$AWS" re-enters this function and recurses forever.
aws() { command "$AWS" --region "$AWS_REGION" "$@"; }

echo "Region  : $REGION_ARG  ->  $AWS_REGION"
echo "Instance: $INSTANCE_NAME ($INSTANCE_TYPE)"
echo "Tunnel  : SOCKS5 127.0.0.1:$LOCAL_PORT"
echo

# ---- detect your public IP (the only address allowed inbound) ------------
MY_IP="$(curl -s --max-time 8 https://checkip.amazonaws.com 2>/dev/null | tr -d '[:space:]')"
[ -n "$MY_IP" ] || { echo "ERROR: could not detect your public IP"; exit 1; }
echo ">> Locking inbound SSH to $MY_IP/32"

# ---- per-session SSH key (local only; pushed via EIC, never an EC2 key pair) --
# Lives in a gitignored dir next to the script. We only ever rm -f the files
# below — never the directory itself.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEY_DIR="${KEY_DIR:-$SCRIPT_DIR/.keys}"
mkdir -p "$KEY_DIR"
KEY_FILE="$KEY_DIR/id"
KNOWN_HOSTS="$KEY_DIR/known_hosts"
rm -f "$KEY_FILE" "$KEY_FILE.pub"        # avoid ssh-keygen's overwrite prompt
ssh-keygen -t ed25519 -N "" -f "$KEY_FILE" -q

# ---- teardown ------------------------------------------------------------
INSTANCE_ID=""
SG_ID=""
CLEANED=0
cleanup() {
  [ "$CLEANED" -eq 1 ] && return
  CLEANED=1
  echo
  if [ -n "$INSTANCE_ID" ]; then
    echo ">> Terminating instance $INSTANCE_ID ..."
    aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" >/dev/null 2>&1 || \
      echo ">> WARNING: terminate may have failed."
    echo ">> Waiting for it to terminate (so the security group can be freed) ..."
    aws ec2 wait instance-terminated --instance-ids "$INSTANCE_ID" >/dev/null 2>&1 || true
  fi
  if [ -n "$SG_ID" ]; then
    echo ">> Deleting security group $SG_ID ..."
    aws ec2 delete-security-group --group-id "$SG_ID" >/dev/null 2>&1 || \
      echo ">> WARNING: SG delete failed — delete it manually once the instance is gone."
  fi
  echo ">> Deleting key pair $KEY_NAME ..."
  aws ec2 delete-key-pair --key-name "$KEY_NAME" >/dev/null 2>&1 || \
    echo ">> WARNING: key-pair delete failed — delete it manually: ec2 delete-key-pair --key-name $KEY_NAME"
  # Remove only the key files we created; leave the .keys dir in place.
  rm -f "$KEY_FILE" "$KEY_FILE.pub" "$KNOWN_HOSTS"

  echo ">> Live instances still in $AWS_REGION:"
  live=$(aws ec2 describe-instances \
    --filters "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query "Reservations[].Instances[].{Id:InstanceId,State:State.Name,Name:Tags[?Key=='Name']|[0].Value}" \
    --output text 2>/dev/null)
  if [ -z "$live" ]; then
    echo "   (none) — nothing is billing now."
  else
    echo "$live" | sed 's/^/   /'
    echo ">> WARNING: instance(s) above are still alive. Delete with:"
    echo "   $AWS --region $AWS_REGION ec2 terminate-instances --instance-ids <ID>"
  fi
}
trap cleanup EXIT INT TERM

# ---- clear leftovers from an unclean exit so create succeeds -------------
OLD_IDS=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=$INSTANCE_NAME" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query "Reservations[].Instances[].InstanceId" --output text 2>/dev/null || true)
if [ -n "$OLD_IDS" ]; then
  echo ">> Found leftover instance(s): $OLD_IDS — terminating first ..."
  aws ec2 terminate-instances --instance-ids $OLD_IDS >/dev/null 2>&1 || true
  aws ec2 wait instance-terminated --instance-ids $OLD_IDS >/dev/null 2>&1 || true
fi
OLD_SG=$(aws ec2 describe-security-groups --group-names "$SG_NAME" \
  --query "SecurityGroups[0].GroupId" --output text 2>/dev/null || true)
if [ -n "$OLD_SG" ] && [ "$OLD_SG" != "None" ]; then
  aws ec2 delete-security-group --group-id "$OLD_SG" >/dev/null 2>&1 || true
fi
# A leftover key pair of the same name would make import-key-pair fail.
aws ec2 delete-key-pair --key-name "$KEY_NAME" >/dev/null 2>&1 || true

# ---- resolve the latest Amazon Linux 2023 arm64 AMI in this region -------
echo ">> Resolving latest Amazon Linux 2023 AMI ..."
AMI_ID="${AMI_ID:-$(aws ec2 describe-images --owners amazon \
  --filters "Name=name,Values=al2023-ami-2023.*-arm64" "Name=state,Values=available" \
  --query "reverse(sort_by(Images,&CreationDate))[0].ImageId" --output text)}"
[ -n "$AMI_ID" ] && [ "$AMI_ID" != "None" ] || { echo "ERROR: could not resolve an AMI"; exit 1; }
echo "   $AMI_ID"

# ---- default VPC + locked-down security group ----------------------------
VPC_ID="$(aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" \
  --query "Vpcs[0].VpcId" --output text)"
[ -n "$VPC_ID" ] && [ "$VPC_ID" != "None" ] || { echo "ERROR: no default VPC in $AWS_REGION"; exit 1; }

echo ">> Creating security group $SG_NAME (SSH from $MY_IP/32 only) ..."
SG_ID="$(aws ec2 create-security-group --group-name "$SG_NAME" \
  --description "Region Proxy Switcher - SSH from one IP only" \
  --vpc-id "$VPC_ID" --query GroupId --output text)"
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" \
  --protocol tcp --port 22 --cidr "$MY_IP/32" >/dev/null

echo ">> Importing ephemeral public key as key pair $KEY_NAME ..."
aws ec2 import-key-pair --key-name "$KEY_NAME" \
  --public-key-material "fileb://$KEY_FILE.pub" >/dev/null

echo ">> Launching instance ..."
# --key-name: the ephemeral key imported above (private half stays local).
# No --iam-instance-profile: the box carries no AWS credentials. IMDSv2 required.
INSTANCE_ID="$(aws ec2 run-instances \
  --image-id "$AMI_ID" \
  --instance-type "$INSTANCE_TYPE" \
  --key-name "$KEY_NAME" \
  --security-group-ids "$SG_ID" \
  --metadata-options "HttpTokens=required,HttpEndpoint=enabled" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
  --count 1 --query "Instances[0].InstanceId" --output text)"
echo "   $INSTANCE_ID"

echo ">> Waiting for it to enter running ..."
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"
PUBLIC_IP="$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
  --query "Reservations[0].Instances[0].PublicIpAddress" --output text)"
[ -n "$PUBLIC_IP" ] && [ "$PUBLIC_IP" != "None" ] || { echo "ERROR: no public IP assigned"; exit 1; }
echo ">> Public IP: $PUBLIC_IP"

SSH_OPTS=(-i "$KEY_FILE"
  -o StrictHostKeyChecking=accept-new
  -o UserKnownHostsFile="$KNOWN_HOSTS"
  -o ConnectTimeout=10)

echo ">> Waiting for SSH to come up ..."
ready=0
for _ in $(seq 1 30); do
  if ssh "${SSH_OPTS[@]}" "$SSH_USER@$PUBLIC_IP" true >/dev/null 2>&1; then
    ready=1; break
  fi
  sleep 5
done
[ "$ready" -eq 1 ] || { echo "ERROR: SSH never came up"; exit 1; }

EXIT_IP=$(ssh "${SSH_OPTS[@]}" "$SSH_USER@$PUBLIC_IP" \
  "curl -s --max-time 10 ifconfig.me || echo '?'" 2>/dev/null || echo '?')
echo ">> Exit IP: $EXIT_IP"

echo
echo "=========================================================="
echo "  Proxy READY.  Turn the Chrome extension ON."
echo "  Press Ctrl-C here to disconnect AND delete everything."
echo "=========================================================="
echo

# SOCKS5 tunnel; -N = forward only, no shell. Background + wait so the trap
# fires promptly on Ctrl-C.
ssh "${SSH_OPTS[@]}" \
  -N -D "$LOCAL_PORT" \
  -o ServerAliveInterval=30 \
  -o ExitOnForwardFailure=yes \
  "$SSH_USER@$PUBLIC_IP" &
SSH_PID=$!
wait "$SSH_PID"

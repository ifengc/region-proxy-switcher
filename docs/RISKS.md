# Risks — Region Proxy Switcher

Worst-first. See also the ACCEPTED RISK notes atop `proxy.sh` and `proxy-aws.sh`.
Both Providers share this threat model; per-item notes call out where they differ.

## 1. Billing leak on unclean exit (highest impact)
Teardown is `trap cleanup EXIT INT TERM` — it fires on Ctrl-C / normal exit, but
not on `kill -9`, power loss, or sleep/crash. The instance then keeps billing
(~$6–7/mo if left on). The next launch deletes a leftover of the *same*
name/region, but not a `proxy-jp` left over from a different region. Both scripts
list live instances after each delete so you can spot leftovers.
- **GCP:** no mitigation; delete manually if orphaned.
- **AWS:** same — a self-terminate safety net (`shutdown -h +N` +
  `instance-initiated-shutdown-behavior=terminate`) was *deliberately declined*
  for parity with GCP, so this risk is unmitigated by choice. An orphaned
  security group / key pair don't bill, and a clean re-run sweeps same-named
  leftovers; only the instance costs money.

## 2. Public SSH port
The box exposes port 22 to initiate the tunnel.
- **GCP:** default ephemeral IP + `default-allow-ssh` = port 22 open to
  `0.0.0.0/0`. Low risk (key-only auth, no GCP credentials on the box, VM lives
  minutes) but world-reachable. To shrink: firewall scoped to your IP `/32`, or
  IAP forwarding with `--no-address`.
- **AWS:** already shrunk — a per-session security group allows inbound `tcp/22`
  from your current public IP `/32` only, the box carries no IAM role, and IMDSv2
  is required. The AWS-native way to remove the inbound port entirely (SSH-over-
  SSM, zero ingress) is blocked by IAM permissions today; see ADR 0003.

## 3. `StrictHostKeyChecking=accept-new`
Each launch is a new VM with a new host key, so pinning is meaningless. Residual
first-connect MITM risk is low (GCP IP over Google's network to a box you just
made).

## 4. No end-to-end fail-closed
The extension fails closed (`mandatory: true`) and forces OFF on startup. Gap:
if the script dies while the extension is ON, Chrome breaks until you click OFF
— no IP leak, but a confusing failure.

## 5. Local SOCKS port has no auth
`127.0.0.1:1080` is loopback-only, so only local processes can reach it.
Single-user laptop → negligible.

## 6. Operational sharp edges
- Zone is hardcoded per region; no fallback if it's out of e2-micro capacity.
- No max-lifetime on the VM (see #1).

# Risks — Region Proxy Switcher

Worst-first. See also the ACCEPTED RISK note atop `proxy.sh`.

## 1. Billing leak on unclean exit (highest impact)
Teardown is `trap cleanup EXIT INT TERM` — it fires on Ctrl-C / normal exit, but
not on `kill -9`, power loss, or sleep/crash. The VM then keeps billing
(~$6–7/mo if left on). The next launch deletes a leftover of the *same*
name/zone, but not a `proxy-jp` left over from a different region. The script
lists live `proxy-*` VMs after each delete so you can spot leftovers. Could also
add a `--max-run-duration` self-destruct or an orphan sweep.

## 2. Public SSH port
Default ephemeral IP + `default-allow-ssh` = port 22 open to `0.0.0.0/0`. Low
risk: key-only auth, no GCP credentials on the box, VM lives minutes. To shrink:
firewall scoped to your IP `/32`, or IAP forwarding with `--no-address`.

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

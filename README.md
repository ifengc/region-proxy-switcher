# Region Proxy Switcher

Browse geofenced sites by appearing from a chosen region. Pieces:

- **`proxy.sh`** — GCP Provider. Creates a throwaway GCP VM in the region, opens
  an SSH SOCKS5 tunnel at `127.0.0.1:1080`, and deletes the VM when you quit.
- **`proxy-aws.sh`** — AWS Provider. Same UX on a throwaway EC2 instance (the
  Taiwan region maps to `ap-east-2`, a genuine in-Taiwan AWS region). Same local
  SOCKS port, so the extension needs no changes.
- **`extension/`** — a Chrome extension. One click routes Chrome through the
  tunnel; click again to go direct.

Not a VPN — only Chrome's traffic is proxied. See `CONTEXT.md` for vocabulary
and `docs/adr/` for design decisions (ADR 0003 covers the AWS access model).

## Load the extension (once)

1. Open `chrome://extensions`, enable **Developer mode**.
2. **Load unpacked** → select `extension/`.

## Each session

```bash
./proxy.sh tw          # GCP Provider   (or: jp, us)
./proxy-aws.sh tw      # AWS Provider   (or: jp, us)
```

Pick one Provider per session. Wait for `Proxy READY`, click the extension
(badge turns green `ON`), browse. **Ctrl-C** when done — the tunnel closes and
everything created that run is deleted.

## Notes

- Instances are micro-sized (`e2-micro` on GCP, `t4g.micro` on AWS), created and
  deleted each run — cents per session, nothing bills while idle.
- **AWS access model:** no IAM role on the box (credential-free), IMDSv2
  required, inbound SSH locked to your current public IP `/32` via a per-session
  security group, and a per-session ephemeral key pair the script creates and
  deletes for you. Nothing to pre-create. See ADR 0003.
- **Crash caveat:** teardown needs a clean exit. After a power loss, delete
  manually:
  - GCP: `gcloud compute instances delete proxy-<region> --zone <zone>`
  - AWS: `aws --region <region> ec2 terminate-instances --instance-ids <id>`
    (then delete the `rps-proxy-<region>` security group and key pair). A clean
    re-run also sweeps same-named leftovers.
- Extension ON but tunnel down → pages fail by design (no fallback to your real
  IP). Turn it OFF or start the script.

## Roadmap

- **Domain-list mode** — route only listed domains (the PAC script is the seam).
- **More regions** — add a region to the `case` in `proxy.sh` / `proxy-aws.sh`.
- **AWS zero-inbound upgrade** — switch to SSH-over-SSM once IAM permits (ADR 0003).

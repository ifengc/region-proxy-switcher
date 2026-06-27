# Region Proxy Switcher

Browse geofenced sites by appearing from a chosen region. Two pieces:

- **`proxy.sh`** — creates a throwaway GCP VM in the region, opens an SSH SOCKS5
  tunnel at `127.0.0.1:1080`, and deletes the VM when you quit.
- **`extension/`** — a Chrome extension. One click routes Chrome through the
  tunnel; click again to go direct.

Not a VPN — only Chrome's traffic is proxied. See `CONTEXT.md` for vocabulary
and `docs/adr/` for design decisions.

## Load the extension (once)

1. Open `chrome://extensions`, enable **Developer mode**.
2. **Load unpacked** → select `extension/`.

## Each session

```bash
./proxy.sh tw      # or: jp, us
```

Wait for `Proxy READY`, click the extension (badge turns green `ON`), browse.
**Ctrl-C** when done — the tunnel closes and the VM is deleted.

## Notes

- VM is `e2-micro`, created and deleted each run — cents per session, nothing
  bills while idle.
- **Crash caveat:** teardown needs a clean exit. After a power loss, delete
  manually: `gcloud compute instances delete proxy-<region> --zone <zone>`.
- Extension ON but tunnel down → pages fail by design (no fallback to your real
  IP). Turn it OFF or start the script.

## Roadmap

- **Domain-list mode** — route only listed domains (the PAC script is the seam).
- **More regions** — add a zone to the `case` in `proxy.sh`.

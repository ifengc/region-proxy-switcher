# Region Proxy Switcher

A personal, single-user tool for browsing geofenced sites from outside the
target region. Not a VPN: it routes only Chrome's traffic through a regional
proxy, and spins that proxy up and down on demand so nothing bills while idle.

## Language

**Proxy Switcher** — the Chrome extension. Flips Chrome between direct and
routing through the Exit Proxy.
_Avoid_: VPN, tunnel client

**Exit Proxy** — the proxy Chrome traffic exits through so sites see a regional
IP. Runs on a throwaway cloud instance in the Exit Region (a GCP VM via
`proxy.sh`, or an AWS EC2 instance via `proxy-aws.sh`).
_Avoid_: VPN server, gateway

**Provider** — the cloud that hosts the Exit Proxy for a session: GCP
(`proxy.sh`) or AWS (`proxy-aws.sh`). Same UX and same local SOCKS port, so the
Proxy Switcher is provider-agnostic. A given Exit Region resolves to a different
cloud region per Provider.
_Avoid_: backend

**Exit Region** — the country whose IP you want, mapped to a cloud region per
Provider (Taiwan → GCP `asia-east1` / AWS `ap-east-2`; Japan → `asia-northeast1`
/ `ap-northeast-1`; US → `us-central1` / `us-east-1`). A parameter, never
hardcoded. Only one is active at a time; switching means rerunning the script.
The tunnel always uses the same local SOCKS port, so the extension is
region-agnostic.
_Avoid_: location, endpoint

**Routing Mode** — which traffic goes through the Exit Proxy. v1 is
all-or-nothing (ON = everything). A domain-list mode is planned.
_Avoid_: split tunneling, rules

**Launch / Shutdown** — Launch creates a fresh VM and opens the tunnel;
Shutdown deletes the VM so nothing bills between sessions. The Exit Proxy needs
no installed software, so a new VM is usable immediately.
_Avoid_: deploy, provision, start/stop

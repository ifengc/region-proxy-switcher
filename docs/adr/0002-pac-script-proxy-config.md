# Configure the proxy via a PAC script, not fixedServers

The extension sets Chrome's proxy with a generated PAC script, even though v1's
logic is just `return ON ? "SOCKS5 localhost:1080" : "DIRECT"`.

Why: the roadmap's domain-list mode (route only listed domains) is an allowlist,
which `fixedServers` can't express — it only offers a `bypassList` denylist.
PAC's `FindProxyForURL` can, so the feature becomes an additive change, not a
rewrite.

Note: multi-country didn't drive this. Only one region is active at a time on a
fixed local port, so `fixedServers` would have handled it fine — domain-list is
the sole reason for PAC.

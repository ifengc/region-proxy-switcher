# Use SSH dynamic forwarding as the Exit Proxy, not a proxy daemon

The Exit Proxy is `ssh -D 1080` against the VM's built-in SSHD, giving a local
SOCKS5 proxy at `localhost:1080`. We install no proxy software (Dante,
tinyproxy, Shadowsocks, Xray).

Why: the targets gate by geography, not censorship, so we don't need protocol
obfuscation. SSH forwarding reuses GCP's SSH-key auth, exposes nothing beyond
port 22, and lets the extension always target a fixed `localhost:1080`
regardless of the VM's ephemeral IP. Cost: Launch must run a background `ssh` on
the laptop, not just flip the extension.

// Region Proxy Switcher — single-click toolbar toggle.
// ON  -> Chrome routes all traffic through proxy.sh's SOCKS5 tunnel at
//        127.0.0.1:PORT (which exits in the chosen region).
// OFF -> Chrome goes direct.
//
// PAC (not fixedServers) so a future domain-list mode can use FindProxyForURL.
// See docs/adr/0002.

const PORT = 1080; // must match LOCAL_PORT in proxy.sh

// SOCKS5 (not SOCKS4) so DNS resolves at the remote exit, not locally.
const PAC_ON = `function FindProxyForURL(url, host) { return "SOCKS5 127.0.0.1:${PORT}"; }`;

async function setEnabled(on) {
  if (on) {
    await chrome.proxy.settings.set({
      scope: "regular",
      // mandatory:true => if the tunnel is down, requests fail instead of
      // falling back to direct and leaking your real IP.
      value: { mode: "pac_script", pacScript: { data: PAC_ON, mandatory: true } },
    });
  } else {
    await chrome.proxy.settings.clear({ scope: "regular" });
  }
  await chrome.storage.local.set({ enabled: on });
  await updateBadge(on);
}

async function updateBadge(on) {
  await chrome.action.setBadgeText({ text: on ? "ON" : "OFF" });
  await chrome.action.setBadgeBackgroundColor({ color: on ? "#0a7d1b" : "#888888" });
  await chrome.action.setTitle({
    title: on
      ? `Region Proxy: ON — SOCKS5 127.0.0.1:${PORT} (click to disable)`
      : "Region Proxy: OFF (click to enable)",
  });
}

chrome.action.onClicked.addListener(async () => {
  const { enabled } = await chrome.storage.local.get("enabled");
  await setEnabled(!enabled);
});

// Always start OFF so a stale proxy setting never breaks browsing when no
// tunnel is running.
chrome.runtime.onStartup.addListener(() => setEnabled(false));
chrome.runtime.onInstalled.addListener(() => setEnabled(false));

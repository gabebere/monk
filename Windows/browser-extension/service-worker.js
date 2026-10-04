const nativeHost = "com.gbr.monk";
const policyLifetimeMs = 800;
const authenticationDomains = [
  "account.live.com",
  "accounts.google.com",
  "appleid.apple.com",
  "login.live.com",
  "login.microsoft.com",
  "login.microsoftonline.com"
];

let cachedPolicy = { enforcing: false, allowedDomains: [], revision: 0 };
let cachedAt = 0;
const initialized = chrome.storage.local.get("lastPolicy").then(({ lastPolicy }) => {
  if (lastPolicy?.enforcing === true && Array.isArray(lastPolicy.allowedDomains)) {
    cachedPolicy = lastPolicy;
  }
});

async function loadPolicy() {
  await initialized;
  const now = Date.now();
  if (now - cachedAt < policyLifetimeMs) {
    return cachedPolicy;
  }

  try {
    const response = await chrome.runtime.sendNativeMessage(nativeHost, { type: "policy" });
    cachedPolicy = {
      enforcing: response?.enforcing === true,
      allowedDomains: Array.isArray(response?.allowedDomains) ? response.allowedDomains : [],
      revision: Number(response?.revision ?? 0)
    };
    cachedAt = now;
    await chrome.storage.local.set({ lastPolicy: cachedPolicy });
  } catch {
    // Fail closed only if a policy was already active. A temporarily unavailable
    // host must not silently unlock a running commitment.
    cachedAt = now;
  }
  return cachedPolicy;
}

function domainMatches(host, domain) {
  return host === domain || host.endsWith(`.${domain}`);
}

function isAllowed(rawUrl, policy) {
  if (rawUrl.startsWith(chrome.runtime.getURL("blocked.html"))) {
    return true;
  }

  let url;
  try {
    url = new URL(rawUrl);
  } catch {
    return false;
  }

  if (url.protocol !== "http:" && url.protocol !== "https:") {
    return true;
  }

  const host = url.hostname.toLowerCase().replace(/^www\./, "");
  return policy.allowedDomains.some(domain => domainMatches(host, domain)) ||
    (policy.allowedDomains.length > 0 && authenticationDomains.some(domain => domainMatches(host, domain)));
}

async function enforce(details) {
  if (details.frameId !== 0 || details.tabId < 0) {
    return;
  }

  const policy = await loadPolicy();
  if (!policy.enforcing || isAllowed(details.url, policy)) {
    return;
  }

  const blocked = chrome.runtime.getURL("blocked.html") +
    `?site=${encodeURIComponent(new URL(details.url).hostname)}`;
  try {
    await chrome.tabs.update(details.tabId, { url: blocked });
  } catch {
    // The tab may have closed while the native policy was being read.
  }
}

chrome.webNavigation.onBeforeNavigate.addListener(enforce);
chrome.webNavigation.onCommitted.addListener(enforce);
chrome.tabs.onActivated.addListener(async ({ tabId }) => {
  try {
    const tab = await chrome.tabs.get(tabId);
    if (tab.url) {
      await enforce({ tabId, frameId: 0, url: tab.url });
    }
  } catch {
    // Ignore short-lived tabs.
  }
});

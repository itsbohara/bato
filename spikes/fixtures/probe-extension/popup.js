const state = {target: null, worker: null};
function render() {
  document.querySelector('#result').textContent = JSON.stringify(state, null, 2);
}
function refreshTarget() {
  chrome.tabs.query({active: true, currentWindow: true}, tabs => {
    if (chrome.runtime.lastError) {
      state.target = {error: 'Active tab query failed'};
    } else {
      const tab = tabs[0];
      let fixtureURL = null;
      try {
        const url = new URL(tab?.url);
        if (['http:', 'https:'].includes(url.protocol)
            && ['127.0.0.1', 'localhost'].includes(url.hostname)) fixtureURL = url;
      } catch { /* Missing/hidden/invalid URL is not exposed. */ }
      state.target = {
        activeTabId: tab?.id ?? null,
        urlAllowedLoopback: fixtureURL !== null,
        fixtureOrigin: fixtureURL?.origin ?? null,
        fixturePath: fixtureURL?.pathname ?? null
      };
    }
    render();
  });
}
document.querySelector('#probe').onclick = () => {
  refreshTarget();
  chrome.runtime.sendMessage({type: 'bato-probe', source: 'popup'}, response => {
    state.worker = chrome.runtime.lastError ? {error: 'Worker message failed'} : response;
    render();
  });
};
refreshTarget();

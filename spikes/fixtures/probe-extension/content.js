chrome.runtime.sendMessage({type: 'bato-probe', source: 'content'}, response => {
  const target = document.querySelector('#extension-probe');
  if (target) target.textContent = chrome.runtime.lastError
    ? `Synthetic content script loaded; worker failed: ${chrome.runtime.lastError.message}`
    : `Synthetic content script + worker: ${JSON.stringify(response)}`;
  document.documentElement.dataset.batoProbeContent = 'loaded';
});

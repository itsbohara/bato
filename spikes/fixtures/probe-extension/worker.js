chrome.runtime.onMessage.addListener((message, sender, respond) => {
  if (message.type !== 'bato-probe') return false;
  chrome.storage.local.get({popupCount: 0}).then(async state => {
    const popupCount = state.popupCount + (message.source === 'popup' ? 1 : 0);
    if (message.source === 'popup') await chrome.storage.local.set({popupCount});
    respond({worker: 'responded', popupCount, source: message.source, manifestVersion: chrome.runtime.getManifest().manifest_version});
  }).catch(error => respond({error: error.message}));
  return true;
});

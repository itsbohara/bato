document.querySelector('#probe').onclick = () => {
  chrome.runtime.sendMessage({type: 'bato-probe', source: 'popup'}, response => {
    document.querySelector('#result').textContent = chrome.runtime.lastError
      ? chrome.runtime.lastError.message : JSON.stringify(response, null, 2);
  });
};

const marker = document.querySelector('#marker');
const result = document.querySelector('#profile-result');
function readMarker() {
  result.textContent = JSON.stringify({origin: location.origin, secureContext: isSecureContext,
    localStorage: localStorage.getItem('bato-profile-marker'), cookie: document.cookie}, null, 2);
}
document.querySelector('#save-marker').onclick = () => {
  localStorage.setItem('bato-profile-marker', marker.value);
  document.cookie = `bato_marker=${encodeURIComponent(marker.value)}; SameSite=Strict; Path=/; Max-Age=86400`;
  readMarker();
};
document.querySelector('#read-marker').onclick = readMarker;
readMarker();

const alternateOrigin = new URL(location.href);
alternateOrigin.hostname = 'localhost';
document.querySelector('#alternate-origin').href = alternateOrigin.href;

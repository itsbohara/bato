const label = new URLSearchParams(location.search).get('label') || 'none';
document.title = `Commands ${label}`;
document.getElementById('heading').textContent = `Commands fixture ${label}`;

document.getElementById('upload').addEventListener('change', event => {
  const file = event.target.files[0];
  document.getElementById('upload-result').textContent =
    file ? `Chosen: ${file.name} (${file.size} bytes)` : 'No file chosen';
});

window.addEventListener('message', event => {
  if (event.origin !== location.origin) return;
  document.getElementById('popup-result').textContent = `Popup replied: ${event.data}`;
});

document.getElementById('open-popup').addEventListener('click', () => {
  const popup = window.open('commands-popup.html', 'bato-oauth', 'popup,width=420,height=320');
  document.getElementById('popup-result').textContent = popup ? 'Popup opened' : 'Popup blocked';
});

const navigation = performance.getEntriesByType('navigation')[0];
document.getElementById('nav-type').textContent = `Navigation: ${navigation ? navigation.type : 'unknown'}`;

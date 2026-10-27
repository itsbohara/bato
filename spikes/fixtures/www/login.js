document.querySelector('#login').addEventListener('submit', event => {
  event.preventDefault();
  const matches = document.querySelector('#username').value === 'bato-test@example.invalid'
    && document.querySelector('#password').value === 'BatoDummyOnly-42!';
  document.querySelector('#result').textContent = matches
    ? 'PASS: both expected dummy values are present. Verify they were filled by the extension.'
    : 'Expected dummy values not present. No values were transmitted.';
});

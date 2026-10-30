(() => {
  'use strict';
  const output = document.getElementById('modal-status');
  let activity = 0;
  let result = 'No dialog opened';

  function render() {
    output.textContent = `${result}; activity checks: ${activity}.`;
  }

  document.getElementById('show-alert').addEventListener('click', event => {
    if (!event.isTrusted) return;
    window.alert('Bato synthetic tab-modal alert.');
    result = 'Alert dismissed';
    render();
  });
  document.getElementById('show-confirm').addEventListener('click', event => {
    if (!event.isTrusted) return;
    const accepted = window.confirm('Bato synthetic tab-modal confirmation.');
    result = accepted ? 'Confirmation accepted' : 'Confirmation cancelled';
    render();
  });
  document.getElementById('activity').addEventListener('click', event => {
    if (!event.isTrusted) return;
    activity += 1;
    render();
  });
  render();
})();

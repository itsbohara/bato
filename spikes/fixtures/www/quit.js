(() => {
  'use strict';
  const output = document.getElementById('quit-status');
  let armed = false;
  let activity = 0;

  function render() {
    output.textContent = `${armed ? 'Armed' : 'Disarmed'}; activity checks: ${activity}.`;
  }

  document.getElementById('arm').addEventListener('click', event => {
    if (!event.isTrusted) return;
    armed = true;
    render();
  });
  document.getElementById('disarm').addEventListener('click', event => {
    if (!event.isTrusted) return;
    armed = false;
    render();
  });
  document.getElementById('activity').addEventListener('click', event => {
    if (!event.isTrusted) return;
    activity += 1;
    render();
  });
  addEventListener('beforeunload', event => {
    if (!armed) return;
    event.preventDefault();
    event.returnValue = '';
  });
  render();
})();

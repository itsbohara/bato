// Fixture state/operation checks only; a VM cannot prove browser user activation.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const source = fs.readFileSync(new URL('./www/quit.js', import.meta.url), 'utf8');

function fixture() {
  const elements = new Map(['arm', 'disarm', 'activity', 'quit-status'].map(id => [id, {
    textContent: '',
    listeners: new Map(),
    addEventListener(type, listener) {
      assert.equal(type, 'click');
      assert.equal(this.listeners.has(type), false, 'listener must not be registered twice');
      this.listeners.set(type, listener);
    },
  }]));
  const listeners = new Map();
  const document = {getElementById(id) { assert.ok(elements.has(id)); return elements.get(id); }};
  Object.defineProperty(document, 'cookie', {
    get() { throw new Error('Unexpected cookie read'); },
    set() { throw new Error('Unexpected cookie write'); },
  });
  Object.freeze(document);
  const sandbox = {
    document,
    addEventListener(type, listener) {
      assert.equal(type, 'beforeunload');
      assert.equal(listeners.has(type), false);
      listeners.set(type, listener);
    },
  };
  // Access to persistent/network/native-bridge facilities would fail this harness.
  for (const name of ['fetch', 'XMLHttpRequest', 'WebSocket', 'localStorage',
    'sessionStorage', 'indexedDB', 'caches', 'chrome', 'webkit']) {
    Object.defineProperty(sandbox, name, {get() { throw new Error(`Unexpected facility: ${name}`); }});
  }
  vm.runInNewContext(source, sandbox, {filename: 'quit.js'});
  return {
    status: () => elements.get('quit-status').textContent,
    click: (id, trusted = true) => elements.get(id).listeners.get('click')({isTrusted: trusted}),
    unload() {
      let prevented = 0;
      const event = {returnValue: undefined, preventDefault() { prevented += 1; }};
      listeners.get('beforeunload')(event);
      return {prevented, returnValue: event.returnValue};
    },
    listenerCount: () => listeners.size,
  };
}

const page = fixture();
assert.equal(page.status(), 'Disarmed; activity checks: 0.');
assert.deepEqual(page.unload(), {prevented: 0, returnValue: undefined});
page.click('arm', false);
page.click('activity', false);
assert.equal(page.status(), 'Disarmed; activity checks: 0.');
assert.deepEqual(page.unload(), {prevented: 0, returnValue: undefined});

page.click('arm');
assert.equal(page.status(), 'Armed; activity checks: 0.');
assert.deepEqual(page.unload(), {prevented: 1, returnValue: ''});
page.click('activity');
assert.equal(page.status(), 'Armed; activity checks: 1.');
page.click('disarm', false);
assert.deepEqual(page.unload(), {prevented: 1, returnValue: ''});
page.click('arm');
assert.equal(page.listenerCount(), 1);
page.click('disarm');
assert.equal(page.status(), 'Disarmed; activity checks: 1.');
assert.deepEqual(page.unload(), {prevented: 0, returnValue: undefined});
assert.equal(fixture().status(), 'Disarmed; activity checks: 0.');
console.log('Quit fixture state, trusted-event gating and no-persistence checks passed. Browser activation/dialog acceptance remains untested.');

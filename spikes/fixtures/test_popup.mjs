import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
const source = readFileSync(new URL('./probe-extension/popup.js', import.meta.url), 'utf8');
function popup(tabs, fail = false) {
  const elements = {'#probe': {}, '#result': {}};
  let increments = 0;
  const context = {
    URL,
    document: {querySelector: selector => elements[selector]},
    chrome: {
      runtime: {
        lastError: fail ? {message: 'Do not expose arbitrary details https://private.example/?secret=1'} : undefined,
        sendMessage(message, callback) {increments++; callback({worker: 'responded', popupCount: increments});}
      },
      tabs: {query(filter, callback) {
        assert.equal(filter.active, true); assert.equal(filter.currentWindow, true);
        callback(tabs);
      }}
    }
  };
  vm.runInNewContext(source, context);
  return {elements, result: () => JSON.parse(elements['#result'].textContent)};
}
const controlled = popup([{id: 42, url: 'http://127.0.0.1:8765/login.html?password=secret#token'}]);
assert.deepEqual(controlled.result().target, {activeTabId:42, urlAllowedLoopback:true, fixtureOrigin:'http://127.0.0.1:8765', fixturePath:'/login.html'});
assert.equal(controlled.result().worker, null, 'Opening popup must not increment persisted counter');
controlled.elements['#probe'].onclick();
assert.equal(controlled.result().worker.popupCount, 1);
for (const url of ['https://private.example/work?secret=1#token', 'http://localhost.attacker.example/secret', 'chrome://extensions/', 'file:///private/secret', 'not a url']) {
  const probe = popup([{id: 93, url, title: 'PRIVATE TITLE'}]);
  assert.deepEqual(probe.result().target, {activeTabId:93, urlAllowedLoopback:false, fixtureOrigin:null, fixturePath:null});
  assert.ok(!probe.elements['#result'].textContent.includes('secret'));
  assert.ok(!probe.elements['#result'].textContent.includes('PRIVATE'));
}
assert.equal(popup([]).result().target.activeTabId, null);
assert.equal(popup([{id: 4}]).result().target.urlAllowedLoopback, false);
assert.deepEqual(popup([], true).result().target, {error:'Active tab query failed'});
console.log('Popup fixture: active-tab query, loopback sanitization, no query/fragment/non-loopback leakage, and worker counter preservation passed.');

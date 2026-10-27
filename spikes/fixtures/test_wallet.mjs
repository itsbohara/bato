// Verify request gating and exact test-only signing payload without a real wallet.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
const calls = [];
const elements = Object.fromEntries(['#providers', '#result', '#inspect', '#connect', '#disconnect', '#sign'].map(id => [id, {value: '', append(option) {this.value ||= option.value;}}]));
const listeners = {};
const account = '0x0000000000000000000000000000000000000001';
let connected = false;
let reject = false;
const provider = {on() {}, async request(request) {
  calls.push(request);
  if (reject) throw Object.assign(new Error('User rejected request'), {code: 4001});
  if (request.method === 'eth_requestAccounts') {connected = true; return [account];}
  if (request.method === 'eth_accounts') return connected ? [account] : [];
  if (request.method === 'eth_chainId') return '0x1';
  if (request.method === 'wallet_revokePermissions') {connected = false; return null;}
  if (request.method === 'personal_sign') return '0x' + 'ab'.repeat(65);
  throw new Error('Unexpected method');
}};
const context = {
  document: {querySelector: selector => elements[selector], createElement: () => ({})},
  window: {addEventListener: (name, handler) => listeners[name] = handler, dispatchEvent() {}},
  location: {origin: 'http://127.0.0.1:8765'}, isSecureContext: true,
  Event: class {}, TextEncoder, setTimeout() {}, console
};
vm.runInNewContext(readFileSync(new URL('./www/wallet.js', import.meta.url), 'utf8'), context);
listeners['eip6963:announceProvider']({detail: {info: {uuid: 'probe', name: 'Mock wallet', rdns: 'example.invalid'}, provider}});
assert.equal(calls.length, 0, 'Loading/discovery must not request wallet permissions');
await elements['#sign'].onclick();
assert.deepEqual(calls.map(x => x.method), ['eth_accounts'], 'Signing without connected account must not prompt');
reject = true;
await elements['#connect'].onclick();
assert.match(elements['#result'].textContent, /4001/);
reject = false;
await elements['#connect'].onclick();
await elements['#sign'].onclick();
const signed = calls.find(x => x.method === 'personal_sign');
assert.equal(signed.params[1], account);
assert.equal(Buffer.from(signed.params[0].slice(2), 'hex').toString(), 'Bato compatibility test only; no transaction or authorization.');
await elements['#disconnect'].onclick();
assert.equal(connected, false);
assert.ok(calls.every(x => !['eth_sendTransaction', 'eth_sign', 'eth_signTypedData_v4', 'wallet_addEthereumChain'].includes(x.method)));
console.log('Wallet fixture: no unsolicited permission request; rejection, connection, fixed personal_sign, and revocation gates passed.');

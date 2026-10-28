// Fixture request gating, namespaces and shared/isolated state; not a CEF test.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';

const source = readFileSync(new URL('./www/storage.js', import.meta.url), 'utf8');
const key = 'bato.context-storage.v1.marker';
const cookieName = 'bato_context_storage_v1';
const databaseName = 'bato-context-storage-v1';
const cacheUrl = 'http://127.0.0.1:18765/__bato_context_storage_v1_marker__';
function persistentState() {
  return {local: new Map([['unrelated-key', 'private-value']]), cookies: new Map([['unrelated-cookie', 'private-cookie']]),
    idb: new Map(), cache: new Map(), created: false, calls: []};
}
function windowFor(state, label, search = '?label=' + label) {
  const session = new Map();
  const elements = Object.fromEntries(['#marker', '#result', '#write', '#read', '#heading'].map(id => [id, {value: 'bato-shared-a', disabled: false, textContent: ''}]));
  const calls = state.calls;
  const document = {title: '', querySelector: selector => elements[selector]};
  const context = {document, location: {origin: 'http://127.0.0.1:18765', search}, URLSearchParams, Response, setTimeout, clearTimeout,
    localStorage: {
      setItem(name, value) { assert.equal(name, key); calls.push('local.set'); if (state.failLocal) throw Object.assign(new Error('private exception text'), {name: 'QuotaExceededError'}); state.local.set(name, value); },
      getItem(name) { assert.equal(name, key); calls.push('local.get'); return state.local.get(name) ?? null; }
    },
    sessionStorage: {
      setItem(name, value) { assert.equal(name, key); calls.push('session.set'); session.set(name, value); },
      getItem(name) { assert.equal(name, key); calls.push('session.get'); return session.get(name) ?? null; }
    },
    cookieStore: {
      async set(cookie) {
        assert.equal(cookie.name, cookieName); assert.equal(cookie.path, '/'); assert.equal(cookie.sameSite, 'lax');
        assert.ok(cookie.expires > Date.now()); calls.push('cookie.set'); state.cookies.set(cookie.name, cookie.value);
      },
      async get(name) { assert.equal(name, cookieName); calls.push('cookie.get'); return state.cookies.has(name) ? {name, value: state.cookies.get(name)} : null; }
    },
    indexedDB: {open(name, version) {
      assert.equal(name, databaseName); assert.equal(version, 1); calls.push('idb.open');
      const request = {};
      const database = {
        objectStoreNames: {contains(name) { assert.equal(name, 'markers'); return state.created; }},
        createObjectStore(name) { assert.equal(name, 'markers'); state.created = true; },
        close() { calls.push('idb.close'); },
        transaction(name, mode) {
          assert.equal(name, 'markers'); assert.ok(['readonly', 'readwrite'].includes(mode));
          const transaction = {objectStore(storeName) {
            assert.equal(storeName, 'markers');
            const operation = (write, value, recordKey) => {
              assert.equal(recordKey, 'marker'); const result = {};
              queueMicrotask(() => {
                if (write) state.idb.set(recordKey, value);
                result.result = write ? recordKey : state.idb.get(recordKey);
                result.onsuccess?.();
                queueMicrotask(() => transaction.oncomplete?.());
              });
              return result;
            };
            return {put: (value, recordKey) => operation(true, value, recordKey), get: recordKey => operation(false, null, recordKey)};
          }};
          return transaction;
        }
      };
      request.result = database;
      queueMicrotask(() => { if (!state.created) request.onupgradeneeded?.(); request.onsuccess?.(); });
      return request;
    }},
    caches: {async open(name) {
      assert.equal(name, databaseName); calls.push('cache.open');
      return {
        async put(url, response) { assert.equal(url, cacheUrl); calls.push('cache.put'); state.cache.set(url, await response.text()); },
        async match(url) { assert.equal(url, cacheUrl); calls.push('cache.match'); return state.cache.has(url) ? new Response(state.cache.get(url)) : undefined; }
      };
    }}
  };
  // Reading document.cookie would expose unrelated cookies: deliberately fail.
  Object.defineProperty(document, 'cookie', {get() { throw new Error('Do not read all cookies'); }});
  vm.runInNewContext(source, context);
  return {elements, document, context, read: async () => { await elements['#read'].onclick(); return JSON.parse(elements['#result'].textContent); },
    write: async marker => { elements['#marker'].value = marker; await elements['#write'].onclick(); return JSON.parse(elements['#result'].textContent); }};
}

const shared = persistentState();
const a1 = windowFor(shared, 'A1');
const a2 = windowFor(shared, 'A2');
const isolated = persistentState();
const b = windowFor(isolated, 'B');
assert.deepEqual(shared.calls, [], 'Load must not access storage');
assert.deepEqual(isolated.calls, []);
assert.equal(a1.document.title, 'Bato storage fixture A1');
const rejected = await a1.write('private-value');
assert.ok(rejected.error); assert.equal(shared.calls.length, 0, 'Invalid marker must not reach any store');
const written = await a1.write('bato-shared-a');
for (const result of Object.values(written.stores)) assert.deepEqual(result, {status: 'ok', value: 'bato-shared-a'});
const seenByA2 = await a2.read();
for (const name of ['localStorage', 'cookie', 'indexedDB', 'cacheStorage']) assert.equal(seenByA2.stores[name].value, 'bato-shared-a');
assert.equal(seenByA2.stores.sessionStorage.value, null, 'Separate tab must use independent session storage');
for (const result of Object.values((await b.read()).stores)) assert.equal(result.value, null, 'Isolated state must start empty');
await b.write('bato-isolated-b');
assert.equal((await a1.read()).stores.cookie.value, 'bato-shared-a');
const restartedA = windowFor(shared, 'A1');
const afterRestart = await restartedA.read();
assert.equal(afterRestart.stores.indexedDB.value, 'bato-shared-a');
assert.equal(afterRestart.stores.cacheStorage.value, 'bato-shared-a');
assert.equal(afterRestart.stores.sessionStorage.value, null);
assert.equal(shared.local.get('unrelated-key'), 'private-value');
assert.equal(shared.cookies.get('unrelated-cookie'), 'private-cookie');
shared.local.set(key, 'private unexpected content');
assert.deepEqual((await a1.read()).stores.localStorage, {status: 'unexpected-value'});
shared.failLocal = true;
const partial = await a1.write('bato-partial');
assert.deepEqual(partial.stores.localStorage, {status: 'error', error: 'QuotaExceededError'});
assert.equal(partial.stores.indexedDB.value, 'bato-partial', 'One store failure must not suppress other results');
assert.doesNotMatch(a1.elements['#result'].textContent, /private/);
assert.equal(a1.elements['#write'].disabled, false); assert.equal(a1.elements['#read'].disabled, false);
const unavailable = windowFor(persistentState(), 'B', '?label=private-query');
delete unavailable.context.cookieStore; delete unavailable.context.indexedDB; delete unavailable.context.caches;
const missing = await unavailable.read();
for (const name of ['cookie', 'indexedDB', 'cacheStorage']) assert.equal(missing.stores[name].error, 'Unavailable');
assert.equal(unavailable.document.title, '', 'Unknown query values must not enter title');
assert.doesNotMatch(unavailable.elements['#result'].textContent, /private-query/);
console.log('Storage fixture: explicit request gating, fixed namespaces, shared/isolated mock stores, tab sessions, partial failures and output sanitization passed.');

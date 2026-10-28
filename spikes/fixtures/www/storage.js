'use strict';
const storageMarkerKey = 'bato.context-storage.v1.marker';
const storageCookieName = 'bato_context_storage_v1';
const storageDatabaseName = 'bato-context-storage-v1';
const storageCacheName = 'bato-context-storage-v1';
const storageCacheUrl = location.origin + '/__bato_context_storage_v1_marker__';
const storageInput = document.querySelector('#marker');
const storageOutput = document.querySelector('#result');
const storageButtons = [document.querySelector('#write'), document.querySelector('#read')];
const storageLabel = new URLSearchParams(location.search).get('label');
if (['A1', 'A2', 'B'].includes(storageLabel)) {
  document.title = 'Bato storage fixture ' + storageLabel;
  document.querySelector('#heading').textContent = 'Controlled storage fixture ' + storageLabel;
}
function validStorageMarker(value) {
  return typeof value === 'string' && /^bato-[a-z0-9_-]{1,40}$/.test(value);
}
function storageFailure(name = 'StorageError') {
  return Object.assign(new Error(), {name});
}
function storageValue(value) {
  if (value === null || value === undefined) return {status: 'ok', value: null};
  // Never display an unexpected value, even if another page used this test key.
  return validStorageMarker(value) ? {status: 'ok', value} : {status: 'unexpected-value'};
}
function storageDeadline(operation) {
  let timer;
  return Promise.race([
    Promise.resolve().then(operation),
    new Promise((_, reject) => { timer = setTimeout(() => reject(storageFailure('TimeoutError')), 8000); })
  ]).finally(() => clearTimeout(timer));
}
function openStorageDatabase() {
  return new Promise((resolve, reject) => {
    if (!globalThis.indexedDB) return reject(storageFailure('Unavailable'));
    const request = indexedDB.open(storageDatabaseName, 1);
    let blocked = false;
    request.onupgradeneeded = () => {
      if (!request.result.objectStoreNames.contains('markers')) request.result.createObjectStore('markers');
    };
    request.onblocked = () => { blocked = true; reject(storageFailure('BlockedError')); };
    request.onerror = () => reject(request.error || storageFailure());
    request.onsuccess = () => {
      if (blocked) request.result.close();
      else resolve(request.result);
    };
  });
}
async function databaseMarker(write, marker) {
  const database = await openStorageDatabase();
  try {
    return await new Promise((resolve, reject) => {
      const transaction = database.transaction('markers', write ? 'readwrite' : 'readonly');
      const store = transaction.objectStore('markers');
      const request = write ? store.put(marker, 'marker') : store.get('marker');
      let result = null;
      request.onsuccess = () => { result = write ? marker : request.result; };
      request.onerror = () => reject(request.error || storageFailure());
      transaction.oncomplete = () => resolve(result);
      transaction.onerror = () => reject(transaction.error || storageFailure());
      transaction.onabort = () => reject(transaction.error || storageFailure('AbortError'));
    });
  } finally { database.close(); }
}
const storageOperations = {
  localStorage: async (write, marker) => {
    if (write) localStorage.setItem(storageMarkerKey, marker);
    return localStorage.getItem(storageMarkerKey);
  },
  cookie: async (write, marker) => {
    // CookieStore.get(name) avoids reading or displaying unrelated cookies.
    if (!globalThis.cookieStore) throw storageFailure('Unavailable');
    if (write) await cookieStore.set({name: storageCookieName, value: marker, path: '/', sameSite: 'lax', expires: Date.now() + 86400000});
    return (await cookieStore.get(storageCookieName))?.value ?? null;
  },
  indexedDB: databaseMarker,
  cacheStorage: async (write, marker) => {
    if (!globalThis.caches) throw storageFailure('Unavailable');
    const cache = await caches.open(storageCacheName);
    if (write) await cache.put(storageCacheUrl, new Response(marker, {headers: {'Content-Type': 'text/plain'}}));
    const response = await cache.match(storageCacheUrl);
    return response ? response.text() : null;
  },
  sessionStorage: async (write, marker) => {
    if (write) sessionStorage.setItem(storageMarkerKey, marker);
    return sessionStorage.getItem(storageMarkerKey);
  }
};
async function runStorageOperation(write) {
  const marker = storageInput.value;
  if (write && !validStorageMarker(marker)) {
    storageOutput.textContent = JSON.stringify({operation: 'write', error: 'Use a synthetic bato- marker matching the displayed format.'}, null, 2);
    return;
  }
  storageButtons.forEach(button => { button.disabled = true; });
  try {
    const results = await Promise.all(Object.entries(storageOperations).map(async ([name, operation]) => {
      try { return [name, storageValue(await storageDeadline(() => operation(write, marker)))]; }
      catch (error) {
        // Only fixed error categories, never exception messages or storage data.
        const allowed = ['Unavailable', 'BlockedError', 'AbortError', 'TimeoutError', 'SecurityError', 'QuotaExceededError'];
        return [name, {status: 'error', error: allowed.includes(error?.name) ? error.name : 'StorageError'}];
      }
    }));
    storageOutput.textContent = JSON.stringify({operation: write ? 'write' : 'read', stores: Object.fromEntries(results)}, null, 2);
  } finally { storageButtons.forEach(button => { button.disabled = false; }); }
}
document.querySelector('#write').onclick = () => runStorageOperation(true);
document.querySelector('#read').onclick = () => runStorageOperation(false);

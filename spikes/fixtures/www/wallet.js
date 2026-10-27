const select = document.querySelector('#providers');
const output = document.querySelector('#result');
const providers = new Map();
const message = 'Bato compatibility test only; no transaction or authorization.';
function show(value) { output.textContent = JSON.stringify(value, null, 2); }
function register(key, name, provider) {
  if (providers.has(key)) return;
  providers.set(key, provider);
  const option = document.createElement('option'); option.value = key; option.textContent = name;
  select.append(option);
  provider.on?.('accountsChanged', accounts => show({event: 'accountsChanged', accounts}));
  provider.on?.('chainChanged', chainId => show({event: 'chainChanged', chainId}));
}
window.addEventListener('eip6963:announceProvider', event => {
  const detail = event.detail;
  if (detail?.info?.uuid && detail?.provider?.request) {
    register(detail.info.uuid, `${detail.info.name} (${detail.info.rdns})`, detail.provider);
  }
});
window.dispatchEvent(new Event('eip6963:requestProvider'));
setTimeout(() => {
  if (!providers.size && window.ethereum?.request) register('legacy', 'Legacy window.ethereum (verify wallet identity)', window.ethereum);
  if (!providers.size) show({status: 'No injected provider found', secureContext: isSecureContext});
}, 1000);
async function run(operation) {
  try {
    const provider = providers.get(select.value);
    if (!provider) throw new Error('Select an injected provider first.');
    await operation(provider);
  } catch (error) { show({error: error.message, code: error.code ?? null}); }
}
document.querySelector('#inspect').onclick = () => run(async provider => {
  show({origin: location.origin, accounts: await provider.request({method: 'eth_accounts'}),
    chainId: await provider.request({method: 'eth_chainId'})});
});
document.querySelector('#connect').onclick = () => run(async provider => {
  show({origin: location.origin, accounts: await provider.request({method: 'eth_requestAccounts'})});
});
document.querySelector('#disconnect').onclick = () => run(async provider => {
  await provider.request({method: 'wallet_revokePermissions', params: [{eth_accounts: {}}]});
  show({revoked: true, accounts: await provider.request({method: 'eth_accounts'})});
});
document.querySelector('#sign').onclick = () => run(async provider => {
  const accounts = await provider.request({method: 'eth_accounts'});
  if (!accounts[0]) throw new Error('Connect a disposable test account first.');
  const hex = '0x' + Array.from(new TextEncoder().encode(message), byte => byte.toString(16).padStart(2, '0')).join('');
  const signature = await provider.request({method: 'personal_sign', params: [hex, accounts[0]]});
  show({message, account: accounts[0], signature, signatureShapeValid: /^0x[0-9a-f]{130}$/i.test(signature),
    note: 'Shape only; independently recover the signer to establish cryptographic validity.'});
});

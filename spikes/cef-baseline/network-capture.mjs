// Capture network metadata only for synthetic loopback fixtures; no bodies or secrets.
const fixture = new URL(process.argv[2] ?? 'http://127.0.0.1:18765/');
if (fixture.protocol !== 'http:' || fixture.hostname !== '127.0.0.1') throw new Error('Use the numeric IPv4 loopback fixture origin only');
const fixtureOrigin = fixture.origin;
const targets = await (await fetch('http://localhost:9223/json/list')).json();
const target = targets.find(t => t.type === 'page' && t.url === fixtureOrigin + '/blocking.html');
if (!target) throw new Error('Open the controlled blocking fixture first');
const ws = new WebSocket(target.webSocketDebuggerUrl);
const requests = new Map();
const events = [];
const timer = setTimeout(() => { console.log(JSON.stringify({events}, null, 2)); ws.close(); }, 25000);
ws.addEventListener('open', () => ws.send(JSON.stringify({id: 1, method:'Network.enable'})));
ws.addEventListener('message', ({data}) => {
 const msg = JSON.parse(data);
 if (msg.id === 1) console.error('ARMED: Network observer ready for CUA reload');
 const p = msg.params;
 if (!p) return;
 if (msg.method === 'Network.requestWillBeSent' && p.request.url.startsWith(fixtureOrigin + '/')) {
  requests.set(p.requestId, p.request.url);
  events.push({event:msg.method, requestId:p.requestId, url:p.request.url});
 }
 if (requests.has(p.requestId) && ['Network.loadingFailed', 'Network.responseReceived'].includes(msg.method)) {
  events.push({event:msg.method, url:requests.get(p.requestId), errorText:p.errorText, blockedReason:p.blockedReason, status:p.response?.status});
 }
});
ws.addEventListener('error', error => { clearTimeout(timer); console.error(error); process.exit(1); });

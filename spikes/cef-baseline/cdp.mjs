// Read-only diagnostic evaluation in the disposable CEF spike profile.
// Usage: node cdp.mjs 'chrome://extensions/' 'document.title'
const [urlPart, expression] = process.argv.slice(2);
if (!urlPart || !expression) throw new Error('usage: cdp.mjs URL_SUBSTRING EXPRESSION');
const targets = await (await fetch('http://localhost:9223/json/list')).json();
const target = targets.find(t => t.type === 'page' && t.url.includes(urlPart));
if (!target) throw new Error('No matching page target');
const ws = new WebSocket(target.webSocketDebuggerUrl);
const timeout = setTimeout(() => { console.error('CDP timeout'); process.exit(1); }, 15000);
ws.addEventListener('open', () => ws.send(JSON.stringify({id: 1, method: 'Runtime.evaluate', params: {expression, awaitPromise: true, returnByValue: true}})));
ws.addEventListener('message', ({data}) => {
 const message = JSON.parse(data);
 if (message.id !== 1) return;
 console.log(JSON.stringify(message, null, 2));
 clearTimeout(timeout);
 ws.close();
 if (message.error || message.result?.exceptionDetails) process.exitCode = 1;
});
ws.addEventListener('error', error => { clearTimeout(timeout); console.error(error); process.exit(1); });

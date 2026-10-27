'use strict';
const urls = ['http://127.0.0.1:18765/login.html', 'http://127.0.0.1:18765/wallet.html'];
let ids = [];
let splitId;
let targetWindowId;
const output = document.getElementById('output');
function log(value) { output.textContent += JSON.stringify(value, null, 2) + '\n'; }
async function ownWindow() {
  if (targetWindowId !== undefined) {
    const window = await chrome.windows.get(targetWindowId);
    if (window.type !== 'popup') throw new Error('Selected Views target is no longer a popup window.');
    return window.id;
  }
  const tab = await chrome.tabs.getCurrent();
  if (!tab) throw new Error('Open controller.html as a full browser tab, not an action popup.');
  return tab.windowId;
}
async function listWindows() {
  const windows = await chrome.windows.getAll({populate:false});
  log(windows.map(w=>({id:w.id,type:w.type})));
  return windows;
}
async function usePopup() {
  if (ids.length) throw new Error('Close controlled tabs before changing target window.');
  const popups = (await listWindows()).filter(w=>w.type==='popup');
  if(popups.length!==1) throw new Error('Expected exactly one Views popup; found '+popups.length+'. Target unchanged.');
  targetWindowId=popups[0].id;
  await inspect();
}
async function useOwn() {
  if (ids.length) throw new Error('Close controlled tabs before changing target window.');
  targetWindowId=undefined;
  await inspect();
}
async function inspect() {
  const windowId=await ownWindow();
  const window=await chrome.windows.get(windowId);
  log({createSplit: typeof chrome.tabs.createSplit, unsplit: typeof chrome.tabs.unsplit, windowId, windowType:window.type, target:targetWindowId===undefined?'controller':'explicit-popup'});
  if (ids.length) {
    const tabs = await Promise.all(ids.map(id => chrome.tabs.get(id)));
    log(tabs.map(t => ({id:t.id, windowId:t.windowId, index:t.index, active:t.active, splitViewId:t.splitViewId, pinned:t.pinned, groupId:t.groupId})));
  }
}
async function create(save = true) {
  if (ids.length) throw new Error('Close the existing controlled tabs first.');
  const windowId = await ownWindow();
  if (save) await chrome.storage.local.set({savedPair: urls});
  const a = await chrome.tabs.create({windowId, url:urls[0], active:false});
  ids = [a.id];
  const b = await chrome.tabs.create({windowId, index:a.index+1, url:urls[1], active:false});
  ids.push(b.id);
  log({requestedWindowId:windowId,createdTabs:[a,b].map(t=>({id:t.id,windowId:t.windowId}))});
  await inspect();
  if ([a,b].some(t=>t.windowId!==windowId)) throw new Error('tabs.create redirected away from requested window. Pair not attempted; controlled IDs retained for cleanup or explicit move.');
}
async function move() {
  if (!ids.length) throw new Error('Create controlled tabs first.');
  const windowId=await ownWindow();
  log({moveRequested:{tabIds:ids,windowId}});
  const result=await chrome.tabs.move(ids,{windowId,index:-1});
  const tabs=Array.isArray(result)?result:[result];
  log({movedTabs:tabs.map(t=>({id:t.id,windowId:t.windowId}))});
  if(tabs.some(t=>t.windowId!==windowId))throw new Error('Move did not reach requested window.');
  await inspect();
}
async function pair() {
  if (ids.length !== 2) throw new Error('Create two controlled tabs first.');
  if (typeof chrome.tabs.createSplit !== 'function') throw new Error('createSplit unavailable in this runtime.');
  const requestedWindowId=await ownWindow();
  const tabs=await Promise.all(ids.map(id=>chrome.tabs.get(id)));
  if(tabs.some(t=>t.windowId!==requestedWindowId))throw new Error('Controlled tabs are outside selected target; refusing misleading pair result.');
  splitId = await chrome.tabs.createSplit(ids);
  log({createdSplit:splitId});
  await inspect();
}
async function unpair() {
  if (!Number.isInteger(splitId)) throw new Error('No split created by this controller.');
  await chrome.tabs.unsplit(splitId);
  splitId = undefined;
  await inspect();
}
async function close() {
  for (const id of ids) {
    try { await chrome.tabs.remove(id); } catch (e) { log({closeError:String(e)}); }
  }
  ids=[]; splitId=undefined;
  log({closedControlledTabs:true});
}
async function restore() {
  const saved = (await chrome.storage.local.get('savedPair')).savedPair;
  if (JSON.stringify(saved)!==JSON.stringify(urls)) throw new Error('No matching controlled pair saved. Create once first.');
  await create(false);
  await pair();
}
const actions = {inspect, create, move, pair, unpair, close, restore, windows:listWindows, popup:usePopup, own:useOwn,
  left:async()=>{if(ids.length!==2)throw new Error('No pair');await chrome.tabs.update(ids[0],{active:true});await inspect();},
  right:async()=>{if(ids.length!==2)throw new Error('No pair');await chrome.tabs.update(ids[1],{active:true});await inspect();}};
for (const [name, action] of Object.entries(actions)) document.getElementById(name).addEventListener('click', async()=>{
  const buttons=[...document.querySelectorAll('button')];
  buttons.forEach(b=>b.disabled=true);
  try { await action(); } catch(e) { log({operation:name,error:String(e)}); }
  finally { buttons.forEach(b=>b.disabled=false); }
});
inspect().catch(e=>log({error:String(e)}));

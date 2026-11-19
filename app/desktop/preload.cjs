// The window's only door to the app (docs/milestone-3.md): one frozen object, window.spellmind, with
// one async function per call main.mjs handles, and the status push. It runs sandboxed: no Node,
// no ipcRenderer and no event objects reach the page.
'use strict';

const { contextBridge, ipcRenderer } = require('electron');

const CALLS = ['status', 'setAI', 'signIn', 'cancelSignIn', 'signOut', 'saveKey', 'removeKey', 'connectCustom', 'disconnectCustom', 'chooseAI', 'openKeysPage', 'chooseWow', 'installAddon', 'setLoginItem', 'setApp', 'restartLink', 'openLogs', 'checkUpdate', 'downloadUpdate', 'installUpdate', 'seenNews'];

const api = {};
for (const name of CALLS) api[name] = (payload) => ipcRenderer.invoke(`spellmind:${name}`, payload);
api.onStatus = (callback) => {
  if (typeof callback !== 'function') return () => {};
  const handler = (_e, data) => callback(data);
  ipcRenderer.on('spellmind:status', handler);
  return () => ipcRenderer.removeListener('spellmind:status', handler);
};

contextBridge.exposeInMainWorld('spellmind', Object.freeze(api));

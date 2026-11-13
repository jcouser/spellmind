// Spellmind's window (docs/milestone-3.md): draws the app's status and sends the player's changes.
// Everything goes through window.spellmind (preload.cjs); text is set with textContent only.
'use strict';

const $ = (id) => document.getElementById(id);
const sm = window.spellmind;
let last = null;
let busy = false;
let viewing = null; // the AI the picker shows (its setup), not necessarily the one in use

const EFFORT_NAMES = { minimal: 'Minimal', low: 'Low', medium: 'Medium', high: 'High', xhigh: 'Extra high', max: 'Max' };
const ERRORS = {
  wow_running: 'Quit World of Warcraft completely first (not just log out). New addon files only load after a full restart of WoW.',
  not_a_wow_folder: 'That folder doesn\'t look like WoW: Forever\'s. Pick the _forever_ folder (the one with Interface and WTF in it).',
  port_busy: 'The sign-in couldn\'t start: another sign-in may be open. Try again.',
  browser_failed: 'The browser didn\'t open for the sign-in.',
  cancelled: null,
  network: 'The sign-in couldn\'t reach OpenAI. Check your connection and try again.',
  sign_in_failed: 'OpenAI didn\'t accept the sign-in. Try again.',
  // The sign-in's other endings (the review: shown as raw codes).
  timeout: 'The sign-in timed out. Click Sign in again.',
  no_account: 'That account has no ChatGPT plan Spellmind can use.',
  no_refresh: 'OpenAI didn\'t give Spellmind a lasting sign-in. Sign in again.',
  keystore_error: 'Windows couldn\'t save the sign-in in its credential store.',
};

function ago(iso) {
  if (!iso) return null;
  const s = Math.max(0, Math.round((Date.now() - Date.parse(iso)) / 1000));
  if (s < 60) return 'just now';
  if (s < 3600) return `${Math.round(s / 60)} min ago`;
  if (s < 86400) return `${Math.round(s / 3600)} h ago`;
  return new Date(iso).toLocaleDateString();
}

function toast(text, bad) {
  if (!text) return;
  const t = $('toast');
  t.textContent = text;
  t.className = 'toast' + (bad ? ' bad' : '');
  t.hidden = false;
  clearTimeout(toast.timer);
  toast.timer = setTimeout(() => { t.hidden = true; }, bad ? 9000 : 4500);
}

function fact(el, text, tone) {
  el.textContent = text;
  el.className = tone || '';
}

function options(select, list, value) {
  const want = list.map(o => `${o.value}|${o.label}`).join(',');
  if (select.dataset.list !== want) {
    select.replaceChildren(...list.map(o => { const e = document.createElement('option'); e.value = o.value; e.textContent = o.label; return e; }));
    select.dataset.list = want;
  }
  select.value = value;
}

function draw(s) {
  last = s;
  $('version').textContent = `Version ${s.version}${s.packaged ? '' : ' (from source)'}`;
  const pill = $('pill');
  pill.className = `pill ${s.summary.tone}`;
  $('pillText').textContent = s.summary.text;

  // Setup: what's still to do, in order.
  // Each step with its own button, so nothing says "below" (the review: the folder's button was under
  // the fold). Only the next step to do has one.
  const steps = [
    { done: s.wow.ok, text: s.wow.ok ? `WoW folder: ${s.wow.folder}` : 'Pick your WoW: Forever folder.', button: ['Pick the folder', () => $('chooseWow').click()] },
    { done: s.wow.addon.state !== 'missing', text: 'Install the addon (with WoW closed).', button: ['Install', () => $('installAddon').click()] },
    { done: !!s.ai.ready, text: 'Set up your AI: sign in with your ChatGPT plan, or paste an API key.', button: ['Set it up', () => $('aiPick').closest('section').scrollIntoView({ behavior: 'smooth' })] },
    { done: !!s.run?.hello, text: 'Start WoW and log in: the game says hello here.' },
  ];
  // Shown until the first three are done; the hello is the status card's after that.
  const todo = steps.slice(0, 3).some(x => !x.done);
  $('setupCard').hidden = !todo;
  $('statusCard').hidden = todo;
  const next = steps.find(x => !x.done);
  $('steps').replaceChildren(...steps.map(x => {
    const li = document.createElement('li');
    const span = document.createElement('span');
    span.textContent = x.text;
    li.append(span);
    if (x.done) li.className = 'done';
    if (x === next && x.button) {
      const b = document.createElement('button');
      b.textContent = x.button[0];
      b.addEventListener('click', x.button[1]);
      // Install waits for a folder.
      if (x.button[0] === 'Install') b.disabled = !s.wow.ok;
      li.append(b);
    }
    return li;
  }));

  // Status.
  const r = s.run || {};
  const wowWords = { running: ['Running', 'good'], launched: ['Starting', 'good'], absent: ['Not running', 'muted'], exited: ['Closed', 'muted'] };
  const w = wowWords[r.wow] || [s.link.phase === 'running' ? 'Looking for it…' : 'Not looked for yet', 'muted'];
  fact($('factWow'), w[0], w[1]);
  if (s.link.phase === 'gave-up') fact($('factHello'), 'It kept stopping: click Restart the link below', 'bad');
  else if (s.link.phase === 'restarting') fact($('factHello'), `Restarting in ${Math.round((s.link.delayMs || 0) / 1000)} s`, 'warn');
  else if (s.link.phase === 'setup') fact($('factHello'), 'Waiting for the setup', 'warn');
  else if (r.hello) fact($('factHello'), `Connected since ${new Date(r.hello).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}`, 'good');
  else fact($('factHello'), r.wow === 'running' ? 'Waiting for the addon to say hello' : 'Not yet this session', 'muted');
  // The line the game showed (userLine), not the kind (the audit: "An error: oauth_expired").
  if (r.error) fact($('factLast'), r.errorText || `It failed (${r.error}).`, 'bad');
  else fact($('factLast'), r.lastAt ? ago(r.lastAt) : 'None yet this session', r.lastAt ? '' : 'muted');

  // The AI: the picker (the one in use first, marked), the picked one's setup, then the options of
  // the one in use. Picking one that's set up switches to it; one that isn't shows its setup.
  const ai = s.ai;
  const ais = ai.list || [];
  const using = ais.find(x => x.current) || ais[0];
  if (!viewing || !ais.some(x => x.id === viewing)) viewing = using?.id;
  const shown = ais.find(x => x.id === viewing) || using;
  // "ChatGPT plan (sign in)", "Claude (Anthropic API key)", "Other (OpenAI-compatible)": the plan and
  // OpenAI's API key both say ChatGPT, so each says how it connects.
  const how = (x) => (x.kind === 'signin' ? 'sign in' : x.kind === 'custom' ? 'advanced' : `${x.maker || x.card} API key`);
  // The one in use that isn't ready says so (the review: "in use" beside "Not signed in").
  const mark = (x) => (x.current ? (x.ready ? ' · in use' : ` · in use, ${x.kind === 'signin' ? 'not signed in' : 'not set up'}`) : x.ready ? '' : ' · not set up');
  options($('aiPick'), ais.map(x => ({ value: x.id, label: `${x.card} (${how(x)})${mark(x)}` })), shown?.id);
  // Setting up another AI: the one in use still answers until this one works (the review).
  const still = shown && !shown.current && using?.ready ? `Still using ${using.card} until this one works.` : '';
  for (const id of ['planStill', 'keyStill', 'customStill']) { $(id).textContent = still; $(id).hidden = !still; }
  showBoxErrors();

  $('setupPlan').hidden = shown?.kind !== 'signin';
  $('setupKey').hidden = shown?.kind !== 'key';
  $('setupCustom').hidden = shown?.kind !== 'custom';
  if (shown?.kind === 'signin') {
    fact($('planState'), ai.signingIn ? 'Finish the sign-in in your browser…' : shown.ready ? 'Signed in with your plan.' : 'Not signed in.', shown.ready ? 'good' : ai.signingIn ? 'warn' : 'bad');
    $('signIn').hidden = shown.ready || ai.signingIn;
    $('cancelSignIn').hidden = !ai.signingIn;
    $('signOut').hidden = !shown.ready;
  } else if (shown?.kind === 'key') {
    fact($('keyState'), shown.ready ? `Key saved${shown.current ? ' and in use' : ''}.` : `No key yet. ${shown.card}'s keys start like ${(shown.keyExample || 'a long code').replace(/…$/, '')}…`, shown.ready ? 'good' : 'muted');
    $('saveKey').textContent = shown.ready ? 'Replace key' : 'Save key';
    $('keyInput').placeholder = shown.ready ? 'Paste a new key to replace the saved one' : 'Paste your API key here';
    $('removeKey').hidden = !shown.ready;
    $('openKeys').hidden = !shown.keysUrl;
  } else if (shown?.kind === 'custom') {
    // What it's connected to, and the way out (the review: after Connect only the two boxes stayed).
    const c = shown.custom;
    $('customNow').hidden = !c;
    if (c) {
      let host = c.baseUrl;
      try { host = new URL(c.baseUrl).host; } catch { /* as written */ }
      $('customState').textContent = `Connected to ${c.model} at ${host}${c.keyHost ? ', key saved' : ''}.`;
      if (document.activeElement?.tagName !== 'INPUT') {
        if (!$('customUrl').value) $('customUrl').value = c.baseUrl || '';
        if (!$('customModel').value) $('customModel').value = c.model || '';
      }
    }
  }

  // The options belong to the AI in use.
  $('aiOptions').hidden = $('aiOptionsNote').hidden = !shown?.current || !ai.ready;
  options($('model'), (ai.models || []).map(m => ({ value: m.id, label: m.label })), ai.model);
  $('model').disabled = (ai.models || []).length < 2;
  options($('effort'), (ai.efforts || []).map(e => ({ value: e, label: EFFORT_NAMES[e] || e })), ai.effort);
  $('effort').hidden = $('effort').previousElementSibling.hidden = !(ai.efforts || []).length;
  $('search').checked = !!ai.search && !!ai.hasSearch;
  $('search').disabled = !ai.hasSearch;
  $('searchText').textContent = ai.hasSearch ? 'Look up game facts on the web' : `${ai.card || 'This AI'} has no web search in Spellmind yet`;

  // WoW.
  $('wowFolder').textContent = s.wow.folder || 'Not picked yet';
  $('chooseWow').textContent = s.wow.folder ? 'Change' : 'Pick the folder';
  const a = s.wow.addon;
  const addonWords = {
    missing: ['Not installed.', 'bad', 'Install'],
    current: ['Installed and up to date.', 'good', 'Reinstall', true],
    outdated: [`An update is ready (${a.changed || 0} changed, ${a.added || 0} new file${a.added === 1 ? '' : 's'}).`, 'warn', 'Update'],
  };
  // A newer addon from CurseForge or WowUp: not an update, and the app leaves it (install.mjs shouldUpdate).
  if (a.state === 'outdated' && a.newerInstalled) addonWords.outdated = [`A newer addon is installed (${a.installedVersion}; this app has ${a.version}). Update the app to match.`, 'warn', `Use ${a.version} instead`, true];
  const aw = addonWords[a.state] || addonWords.missing;
  fact($('addonState'), aw[0], aw[1]);
  $('installAddon').textContent = aw[2];
  // Nothing to do: a quiet button, not the main action (the review).
  $('installAddon').className = aw[3] ? 'quiet' : '';
  $('installAddon').disabled = !s.wow.ok;

  // The app.
  $('loginItem').checked = !!s.loginItem;
  for (const el of document.querySelectorAll('[data-app]')) el.checked = !!s.app?.[el.dataset.app];

  // Activity.
  const list = s.activity.length ? s.activity.map(x => {
    const li = document.createElement('li');
    const t = document.createElement('time');
    t.textContent = new Date(x.at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    const span = document.createElement('span');
    span.textContent = x.line;
    li.append(t, span);
    return li;
  }) : [Object.assign(document.createElement('li'), { className: 'empty', textContent: 'Nothing yet this session.' })];
  $('activity').replaceChildren(...list);
}

// The last failure of each setup box, shown in it until the next try (the review: a toast gone in 9 s
// left nothing to reread). Cleared on success and when the picker moves.
const boxErr = {};
function showBoxErrors() {
  for (const id of ['planErr', 'keyErr', 'customErr', 'wowErr']) {
    const el = $(id);
    el.textContent = boxErr[id] || '';
    el.hidden = !boxErr[id];
  }
}

// One action at a time: its button says what's happening ("Testing…"), the other controls wait (the
// review: a click made meanwhile was dropped and the switch flipped back). A failure's words go in its
// box when it has one, else a toast.
async function act(button, fn, done, { box = null, busyText = null } = {}) {
  if (busy) return;
  busy = true;
  const controls = [...document.querySelectorAll('main button, main select, main input')].filter(el => !el.disabled);
  for (const el of controls) el.disabled = true;
  const label = button ? button.textContent : null;
  if (button && busyText) button.textContent = busyText;
  try {
    const r = await fn();
    if (r && r.ok === false) {
      const words = r.detail || (r.error in ERRORS ? ERRORS[r.error] : `That didn't work (${r.error}).`);
      if (words && box) boxErr[box] = words;
      else if (words) toast(words, true);
    } else {
      if (box) delete boxErr[box];
      if (done) toast(typeof done === 'function' ? done(r) : done);
    }
  } finally {
    busy = false;
    for (const el of controls) el.disabled = false;
    if (button && busyText) button.textContent = label;
    draw(await sm.status());
  }
}

$('signIn').addEventListener('click', () => {
  // The sign-in waits on the browser; the window stays usable meanwhile (Cancel).
  delete boxErr.planErr;
  sm.signIn().then((r) => {
    if (r && r.ok) toast(`Signed in${r.plan ? ` with your ChatGPT ${r.plan} plan` : ''}.`);
    else if (r && r.error && ERRORS[r.error] !== null) boxErr.planErr = ERRORS[r.error] || `The sign-in didn't finish (${r.error}).`;
    sm.status().then(draw);
  });
  setTimeout(() => sm.status().then(draw), 300);
});
$('cancelSignIn').addEventListener('click', () => act(null, () => sm.cancelSignIn()));
// Picking an AI: one that's set up is used at once; another shows how to set it up.
$('aiPick').addEventListener('change', (e) => {
  viewing = e.target.value;
  for (const k of ['planErr', 'keyErr', 'customErr']) delete boxErr[k];
  const x = (last?.ai?.list || []).find(a => a.id === viewing);
  if (x && x.ready && !x.current) act(null, () => sm.chooseAI(viewing), `Now using ${x.card}.`);
  else if (last) draw(last);
});
// A key is for the AI its shape says, which may not be the one on screen: the picker follows it, and
// says so (the review: a ChatGPT key pasted while Grok showed left Grok's box saying "No key yet").
// The key from its field (the player, 2026-11-13: reading the clipboard failed): sent once, the field
// cleared whatever happens. A key is for the AI its shape says, which may not be the one on screen: the
// picker follows it, and says so.
function saveKey() {
  const key = $('keyInput').value;
  $('keyInput').value = '';
  if (!key.trim()) { boxErr.keyErr = 'Paste your API key in the box first.'; showBoxErrors(); return; }
  const was = viewing;
  act($('saveKey'), () => sm.saveKey({ key }), (r) => {
    viewing = r.id || viewing;
    const other = r.id && r.id !== was ? `That's a ${r.card} key: now using ${r.card}. ` : '';
    return `${other}${r.card}: key saved and working.`;
  }, { box: 'keyErr', busyText: 'Testing…' });
}
$('saveKey').addEventListener('click', saveKey);
$('keyInput').addEventListener('keydown', (e) => { if (e.key === 'Enter') saveKey(); });
$('removeKey').addEventListener('click', () => act($('removeKey'), () => sm.removeKey(viewing), 'Key removed.', { box: 'keyErr' }));
$('openKeys').addEventListener('click', () => act(null, () => sm.openKeysPage(viewing)));
$('connectCustom').addEventListener('click', () => act($('connectCustom'),
  () => { const key = $('customKey').value; $('customKey').value = ''; return sm.connectCustom({ baseUrl: $('customUrl').value, model: $('customModel').value, key }); },
  'Connected and working.', { box: 'customErr', busyText: 'Testing…' }));
$('disconnectCustom').addEventListener('click', () => act($('disconnectCustom'), () => sm.disconnectCustom(), 'Disconnected.', { box: 'customErr' }));
$('signOut').addEventListener('click', () => act($('signOut'), () => sm.signOut(), 'Signed out.', { box: 'planErr' }));
$('model').addEventListener('change', (e) => act(null, () => sm.setAI({ model: e.target.value }), 'Saved.'));
$('effort').addEventListener('change', (e) => act(null, () => sm.setAI({ effort: e.target.value }), 'Saved.'));
$('search').addEventListener('change', (e) => act(null, () => sm.setAI({ search: e.target.checked }), 'Saved.'));
$('chooseWow').addEventListener('click', () => act($('chooseWow'), () => sm.chooseWow(), 'Folder saved.', { box: 'wowErr' }));
// A first install says what's next; an update with WoW open says /reload (r.note).
$('installAddon').addEventListener('click', () => {
  const first = last?.wow?.addon?.state === 'missing';
  act($('installAddon'), () => sm.installAddon(), (r) => (first && !r.reload ? 'Addon installed. Start WoW and log in.' : r.note || 'Done.'), { box: 'wowErr', busyText: 'Installing…' });
});
$('loginItem').addEventListener('change', (e) => act(null, () => sm.setLoginItem(e.target.checked)));
for (const el of document.querySelectorAll('[data-app]')) {
  el.addEventListener('change', (e) => act(null, () => sm.setApp({ [e.target.dataset.app]: e.target.checked })));
}
$('restartLink').addEventListener('click', () => act($('restartLink'), () => sm.restartLink(), 'Restarting the link.'));
$('openLogs').addEventListener('click', () => act(null, () => sm.openLogs()));

sm.onStatus(draw);
sm.status().then(draw);
// "2 min ago" moves on by itself.
setInterval(() => { if (last && !busy) draw(last); }, 30000);

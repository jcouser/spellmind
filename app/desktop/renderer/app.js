// Spellmind's window (docs/milestone-3.md): draws the app's status and sends the player's changes.
// Everything goes through window.spellmind (preload.cjs); text is set with textContent only.
'use strict';

const $ = (id) => document.getElementById(id);
const sm = window.spellmind;
let last = null;
let busy = false;

const EFFORT_NAMES = { minimal: 'Minimal', low: 'Low', medium: 'Medium', high: 'High', xhigh: 'Extra high', max: 'Max' };
const ERRORS = {
  wow_running: 'Quit World of Warcraft completely first (not just log out). New addon files only load after a full restart of WoW.',
  not_a_wow_folder: 'That folder doesn\'t look like WoW: Forever\'s. Pick the _forever_ folder (the one with Interface and WTF in it).',
  port_busy: 'The sign-in couldn\'t start: another sign-in may be open. Try again.',
  browser_failed: 'The browser didn\'t open for the sign-in.',
  cancelled: null,
  network: 'The sign-in couldn\'t reach OpenAI. Check your connection and try again.',
  sign_in_failed: 'OpenAI didn\'t accept the sign-in. Try again.',
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
  const steps = [
    { done: s.wow.ok, text: 'Pick your WoW: Forever folder (below).' },
    { done: s.wow.addon.state !== 'missing', text: 'Install the addon, with WoW closed.' },
    { done: !!s.ai.signedIn, text: 'Sign in with your ChatGPT plan.' },
    { done: !!s.run?.hello, text: 'Start WoW and log in: the game says hello here.' },
  ];
  // Shown until the first three are done; the hello is the status card's after that.
  const todo = steps.slice(0, 3).some(x => !x.done);
  $('setupCard').hidden = !todo;
  $('steps').replaceChildren(...steps.map(x => { const li = document.createElement('li'); li.textContent = x.text; if (x.done) li.className = 'done'; return li; }));

  // Status.
  const r = s.run || {};
  const wowWords = { running: ['Running', 'good'], launched: ['Starting', 'good'], absent: ['Not running', 'muted'], exited: ['Closed', 'muted'] };
  const w = wowWords[r.wow] || [s.link.phase === 'running' ? 'Looking for it…' : 'Not looked for yet', 'muted'];
  fact($('factWow'), w[0], w[1]);
  if (s.link.phase === 'restarting') fact($('factHello'), `Restarting in ${Math.round((s.link.delayMs || 0) / 1000)} s`, 'warn');
  else if (s.link.phase === 'setup') fact($('factHello'), 'Waiting for the setup', 'warn');
  else if (r.hello) fact($('factHello'), `Linked (${ago(r.hello)})`, 'good');
  else fact($('factHello'), r.wow === 'running' ? 'Waiting for the addon to say hello' : 'Not yet this session', 'muted');
  if (r.error) fact($('factLast'), `An error: ${r.error}`, 'bad');
  else fact($('factLast'), r.lastAt ? ago(r.lastAt) : 'None yet this session', r.lastAt ? '' : 'muted');

  // The AI.
  const ai = s.ai;
  $('aiName').textContent = ai.name || 'Your AI';
  fact($('aiSigned'), ai.signingIn ? 'Finish the sign-in in your browser…' : ai.signedIn ? 'Signed in with your plan.' : 'Not signed in.', ai.signedIn ? 'good' : ai.signingIn ? 'warn' : 'bad');
  $('signIn').hidden = ai.signedIn || ai.signingIn || !ai.signIn;
  $('cancelSignIn').hidden = !ai.signingIn;
  $('signOut').hidden = !ai.signedIn;
  options($('model'), (ai.models || []).map(m => ({ value: m.id, label: m.label })), ai.model);
  options($('effort'), (ai.efforts || []).map(e => ({ value: e, label: EFFORT_NAMES[e] || e })), ai.effort);
  $('search').checked = !!ai.search;
  $('search').disabled = !ai.hasSearch;

  // WoW.
  $('wowFolder').textContent = s.wow.folder || 'Not picked yet';
  $('chooseWow').textContent = s.wow.folder ? 'Change' : 'Pick the folder';
  const a = s.wow.addon;
  const addonWords = {
    missing: ['Not installed.', 'bad', 'Install'],
    current: ['Installed and up to date.', 'good', 'Reinstall'],
    outdated: [`An update is ready (${a.changed || 0} changed, ${a.added || 0} new file${a.added === 1 ? '' : 's'}).`, 'warn', 'Update'],
  };
  const aw = addonWords[a.state] || addonWords.missing;
  fact($('addonState'), aw[0], aw[1]);
  $('installAddon').textContent = aw[2];
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

async function act(button, fn, done) {
  if (busy) return;
  busy = true;
  if (button) button.disabled = true;
  try {
    const r = await fn();
    if (r && r.ok === false) { const words = r.detail || (r.error in ERRORS ? ERRORS[r.error] : `That didn't work (${r.error}).`); if (words) toast(words, true); }
    else if (done) toast(typeof done === 'function' ? done(r) : done);
  } finally {
    busy = false;
    if (button) button.disabled = false;
    draw(await sm.status());
  }
}

$('signIn').addEventListener('click', () => {
  // The sign-in waits on the browser; the window stays usable meanwhile (Cancel).
  sm.signIn().then((r) => {
    if (r && r.ok) toast(`Signed in${r.plan ? ` with your ChatGPT ${r.plan} plan` : ''}.`);
    else if (r && r.error && ERRORS[r.error] !== null) toast(ERRORS[r.error] || `The sign-in didn't finish (${r.error}).`, true);
    sm.status().then(draw);
  });
  setTimeout(() => sm.status().then(draw), 300);
});
$('cancelSignIn').addEventListener('click', () => act(null, () => sm.cancelSignIn()));
$('signOut').addEventListener('click', () => act($('signOut'), () => sm.signOut(), 'Signed out.'));
$('model').addEventListener('change', (e) => act(null, () => sm.setAI({ model: e.target.value }), 'Saved.'));
$('effort').addEventListener('change', (e) => act(null, () => sm.setAI({ effort: e.target.value }), 'Saved.'));
$('search').addEventListener('change', (e) => act(null, () => sm.setAI({ search: e.target.checked }), 'Saved.'));
$('chooseWow').addEventListener('click', () => act($('chooseWow'), () => sm.chooseWow(), 'Folder saved.'));
$('installAddon').addEventListener('click', () => act($('installAddon'), () => sm.installAddon(), (r) => r.note || 'Done.'));
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

#!/usr/bin/env node
// Spellmind's AI core from the command line: milestone 1's check that the core works on its own,
// with the real key store (Spellmind's own entries), the egress allowlist, the sign-in and the
// providers. No game, no app.
//
//   node tools/chat.mjs signin                       sign in with your ChatGPT plan (opens your browser)
//   node tools/chat.mjs key <provider>               save an API key for anthropic, openai, xai or google (read from stdin)
//   node tools/chat.mjs ask "<question>" [--provider chatgpt] [--model <id>] [--effort low]
//   node tools/chat.mjs models [--provider chatgpt]  the models your sign-in or key can use
//   node tools/chat.mjs forget <provider>            delete that sign-in or key from the key store
//
// Nothing is printed of a key or a token, and the log lines go nowhere.
import { spawn } from 'node:child_process';
import { loadManifests, createProvider, isSignIn } from '../core/ai/providers/index.mjs';
import { createKeyStore } from '../core/ai/security/keystore.mjs';
import { createEgress } from '../core/ai/security/egress.mjs';
import { createSignIns } from '../core/ai/signin/index.mjs';
import { userLine } from '../core/ai/providers/errors.mjs';

const SYSTEM = 'You are Spellmind, an AI companion for World of Warcraft: Forever. Dry humor, warm, practical: the answer first, short paragraphs, no filler.';

function args(argv) {
  const out = { _: [] };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a.startsWith('--')) out[a.slice(2)] = argv[++i];
    else out._.push(a);
  }
  return out;
}

function openInBrowser(url) {
  const [cmd, argv] = process.platform === 'win32' ? ['rundll32.exe', ['url.dll,FileProtocolHandler', url]]
    : process.platform === 'darwin' ? ['open', [url]] : ['xdg-open', [url]];
  spawn(cmd, argv, { detached: true, stdio: 'ignore' }).unref();
}

async function readStdin() {
  let s = '';
  for await (const chunk of process.stdin) s += chunk;
  return s.trim();
}

const manifests = loadManifests();
const byId = id => manifests.find(m => m.id === id) ?? null;
const a = args(process.argv.slice(2));
const [cmd, arg] = a._;
const m = byId(a.provider ?? (cmd === 'key' || cmd === 'forget' ? arg : 'chatgpt'));
if (!m || m.custom) { console.error(`Unknown AI. Pick one of: ${manifests.filter(x => !x.custom).map(x => x.id).join(', ')}`); process.exit(2); }

const keystore = createKeyStore({ backend: 'os' });
// The allowlist: the AI's own hosts, and this computer (the sign-in's redirect listener).
const egress = createEgress({ allowHosts: () => new Set(m.hosts), loopbackOk: true });
const signIns = createSignIns({ keystore, fetch: egress.fetch });
const session = signIns.for(m);
const getKey = async () => (session ? session.credentials() : keystore.get(m.id));
const provider = createProvider(m, { getKey, fetch: egress.fetch });
const say = err => { const l = userLine(err, { provider: m.name, product: 'Spellmind' }); console.error(`${l.headline} ${l.detail}`.trim()); };

switch (cmd) {
  case 'signin': {
    if (!session) { console.error(`${m.name} takes an API key: node tools/chat.mjs key ${m.id}`); process.exit(2); }
    console.log('Opening your browser at OpenAI’s sign-in page…');
    const r = await session.start({ openUrl: async (url) => openInBrowser(url) });
    if (!r.ok) { console.error(`Not signed in (${r.error}).`); process.exit(1); }
    console.log(`Signed in with your ChatGPT ${r.plan ?? ''} plan.`.replace('  ', ' '));
    break;
  }
  case 'key': {
    if (isSignIn(m)) { console.error(`${m.name} signs in: node tools/chat.mjs signin`); process.exit(2); }
    console.error(`Paste your ${m.name} API key and press Enter, then Ctrl+Z (Windows) or Ctrl+D:`);
    const key = await readStdin();
    if (!key) { console.error('No key given.'); process.exit(2); }
    await keystore.set(m.id, key);
    console.log(`Saved in ${keystore.label ?? 'the key store'} under Spellmind.`);
    break;
  }
  case 'models': {
    const v = await provider.validate();
    if (!v.ok) { say(v.error); process.exit(1); }
    console.log(v.models.join('\n'));
    break;
  }
  case 'ask': {
    if (!arg) { console.error('Ask something: node tools/chat.mjs ask "Which profession pairs well with a rogue?"'); process.exit(2); }
    const model = a.model ?? m.models.default;
    let text = '';
    let usage = null;
    for await (const ev of provider.stream({ model, effort: a.effort ?? 'low', system: [{ text: SYSTEM }], messages: [{ role: 'user', content: arg }] })) {
      if (ev.type === 'text') { process.stdout.write(ev.delta); text += ev.delta; }
      else if (ev.type === 'usage') usage = ev.usage;
      else if (ev.type === 'error') { if (text) process.stdout.write('\n'); say(ev.error); process.exit(1); }
    }
    process.stdout.write('\n');
    if (usage) console.error(`\n[${m.name} · ${model} · ${usage.input + usage.cacheRead + usage.cacheWrite} in (${usage.cacheRead} reused), ${usage.output} out${usage.costUsd === 0 ? ' · $0' : ''}]`);
    break;
  }
  case 'forget': {
    await keystore.delete(m.id);
    session?.signOut();
    console.log(`Forgot ${m.name}.`);
    break;
  }
  default:
    console.error('Commands: signin · key <provider> · ask "<question>" · models · forget <provider>');
    process.exit(2);
}

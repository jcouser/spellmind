// Milestone 3 (docs/milestone-3.md): choosing the AI in the desktop app. A key is told apart by its
// shape, tested with a live call, and kept only when it works; it never comes back in a result.
import test from 'node:test';
import assert from 'node:assert/strict';
import { loadManifests } from '../../core/ai/providers/index.mjs';
import { createAISetup } from '../../core/app/ai.mjs';
import { pickAI } from '../../core/app/runner.mjs';
import { aiChoices } from '../../core/app/settings.mjs';

const manifests = loadManifests();
const ANTHROPIC_KEY = 'sk-ant-api03-' + 'A1b2C3d4E5'.repeat(4);

function rig({ status = 200, models = ['claude-sonnet-5-5', 'claude-opus-5-5'], signedIn = false } = {}) {
  const store = new Map();
  const calls = [];
  const keystore = {
    get: async (id) => store.get(id) ?? null,
    set: async (id, v) => { store.set(id, v); },
    delete: async (id) => { store.delete(id); },
  };
  const fetchFor = () => async (url, init) => {
    calls.push({ url: String(url), headers: init?.headers || {} });
    const body = JSON.stringify({ data: models.map(id => ({ id, object: 'model' })), object: 'list', has_more: false });
    return new Response(status === 200 ? body : JSON.stringify({ error: { type: 'authentication_error', message: 'invalid x-api-key' } }), { status, headers: { 'content-type': 'application/json' } });
  };
  const setup = createAISetup({ manifests, keystore, fetchFor, signInFor: () => ({ signedIn: async () => signedIn }) });
  return { setup, store, calls };
}

test('the list: every AI the window offers, how each is set up, which are ready and which is in use', async () => {
  const { setup } = rig({ signedIn: true });
  const list = await setup.list({});
  const ids = list.map(x => x.id);
  for (const id of ['chatgpt', 'anthropic', 'openai', 'google', 'xai', 'custom']) assert.ok(ids.includes(id), id);
  const plan = list.find(x => x.id === 'chatgpt');
  assert.equal(plan.kind, 'signin');
  assert.equal(plan.ready, true);
  assert.equal(plan.current, true, 'the plan by default');
  const claude = list.find(x => x.id === 'anthropic');
  assert.equal(claude.kind, 'key');
  assert.equal(claude.ready, false);
  assert.match(claude.keysUrl, /^https:\/\//);
  assert.equal(list.find(x => x.id === 'custom').kind, 'custom');
});

test('Paste key: the key\'s AI by its shape, a live test, then kept and switched to; never in the result', async () => {
  const { setup, store, calls } = rig();
  const r = await setup.pasteKey({ provider: 'chatgpt', model: 'gpt-6-luna', effort: 'medium', wow: 'W' }, `  "${ANTHROPIC_KEY}"\n`);
  assert.equal(r.ok, true);
  assert.equal(r.id, 'anthropic');
  assert.equal(r.card, 'Claude');
  assert.equal(store.get('anthropic'), ANTHROPIC_KEY, 'unwrapped from the paste\'s quotes and spaces');
  assert.equal(r.cfg.provider, 'anthropic');
  assert.equal(r.cfg.model, undefined, 'the plan\'s model doesn\'t go with it');
  assert.equal(r.cfg.wow, 'W');
  assert.ok(!JSON.stringify(r).includes(ANTHROPIC_KEY), 'the key never comes back');
  assert.match(calls[0].url, /^https:\/\/api\.anthropic\.com\/v1\/models/);
  assert.equal(calls[0].headers['x-api-key'], ANTHROPIC_KEY);
  // The link then runs Claude's default model.
  assert.equal(pickAI(r.cfg).model, 'claude-sonnet-5-5');
  assert.equal(aiChoices(r.cfg).card, 'Claude');
});

test('a key the AI refuses isn\'t kept, and says why in words', async () => {
  const { setup, store } = rig({ status: 401 });
  const r = await setup.pasteKey({}, ANTHROPIC_KEY);
  assert.equal(r.ok, false);
  assert.equal(r.error, 'auth_invalid');
  assert.ok(r.detail.length > 10);
  assert.equal(store.size, 0);
});

test('what isn\'t a key: an empty clipboard, prose, an admin key, a Claude sign-in token, an OpenRouter key', async () => {
  const { setup, calls } = rig();
  assert.equal((await setup.pasteKey({}, '')).error, 'clipboard_empty');
  assert.equal((await setup.pasteKey({}, 'Where do I train Sprint?')).error, 'not_a_key');
  assert.equal((await setup.pasteKey({}, 'sk-ant-admin01-' + 'x'.repeat(40))).error, 'admin_key');
  assert.equal((await setup.pasteKey({}, 'sk-ant-oat01-' + 'x'.repeat(40))).error, 'subscription_token');
  const or = await setup.pasteKey({}, 'sk-or-v1-' + 'a'.repeat(64));
  assert.equal(or.error, 'custom_key');
  assert.match(or.detail, /Other/);
  assert.equal(calls.length, 0, 'nothing is sent for any of them');
});

test('Other: an address and model checked, tested, kept; a model the service doesn\'t list is refused with its list', async () => {
  const { setup, store } = rig({ models: ['llama3.3', 'qwen3:8b'] });
  assert.equal((await setup.connectCustom({}, { baseUrl: 'http://example.com/v1', model: 'llama3.3' })).error, 'https_required');
  assert.equal((await setup.connectCustom({}, { baseUrl: 'https://u:p@example.com/v1', model: 'llama3.3' })).error, 'credentials');
  assert.equal((await setup.connectCustom({}, { baseUrl: 'http://localhost:11434/v1', model: 'bad model!' })).error, 'bad_model');
  const miss = await setup.connectCustom({}, { baseUrl: 'http://localhost:11434/v1', model: 'mistral' });
  assert.equal(miss.error, 'model_not_found');
  assert.match(miss.detail, /llama3\.3/);
  const ok = await setup.connectCustom({ provider: 'chatgpt' }, { baseUrl: 'http://localhost:11434/v1/chat/completions', model: 'llama3.3' }, null);
  assert.equal(ok.ok, true);
  assert.deepEqual(ok.cfg.custom, { baseUrl: 'http://localhost:11434/v1', model: 'llama3.3' });
  assert.equal(ok.cfg.provider, 'custom');
  assert.equal(store.size, 0, 'no key for a server on this computer');
  const p = pickAI(ok.cfg);
  assert.equal(p.model, 'llama3.3');
  assert.equal(p.search, false);
  assert.deepEqual(aiChoices(ok.cfg).efforts, [], 'no thinking menu');
  // With a key from the clipboard: kept under Other.
  const withKey = await setup.connectCustom({}, { baseUrl: 'https://openrouter.ai/api/v1', model: 'llama3.3' }, 'sk-or-v1-' + 'b'.repeat(64));
  assert.equal(withKey.ok, true);
  assert.equal(store.get('custom'), 'sk-or-v1-' + 'b'.repeat(64));
  assert.equal((await setup.connectCustom({}, { baseUrl: 'https://openrouter.ai/api/v1', model: 'llama3.3' }, 'two words')).error, 'not_a_key');
});

test('switching: only to an AI that\'s set up; its own model and a thinking level it has', async () => {
  const { setup } = rig();
  assert.equal((await setup.choose({}, 'anthropic')).error, 'not_ready');
  await setup.pasteKey({}, ANTHROPIC_KEY);
  const r = await setup.choose({ provider: 'chatgpt', model: 'gpt-6-luna', effort: 'medium' }, 'anthropic');
  assert.equal(r.ok, true);
  assert.equal(r.cfg.provider, 'anthropic');
  assert.equal(r.cfg.model, undefined);
  assert.equal(r.cfg.effort, 'medium', 'Claude has medium too');
  assert.equal((await setup.choose({}, 'nope')).error, 'unknown_ai');
  // Removing a key: gone from the store; the plan can't be "removed" this way.
  assert.equal((await setup.removeKey({}, 'anthropic')).ok, true);
  assert.equal((await setup.removeKey({}, 'chatgpt')).error, 'not_a_key_ai');
});

test('the link with a saved setting another AI had: the model falls back, the thinking level goes to the nearest it has', () => {
  const p = pickAI({ provider: 'xai', model: 'claude-opus-5-5', effort: 'max' });
  assert.equal(p.model, 'grok-4.7');
  assert.ok(aiChoices({ provider: 'xai' }).efforts.includes(p.effort));
  assert.equal(pickAI({ provider: 'custom' }).error, 'unknown_ai', 'Other without its settings');
});

test('Other\'s key belongs to its address: a new address without a key drops the old one; the link sends it only there (the security review)', async () => {
  const { setup, store } = rig({ models: ['llama3.3'] });
  const first = await setup.connectCustom({}, { baseUrl: 'https://openrouter.ai/api/v1', model: 'llama3.3' }, 'sk-or-v1-' + 'c'.repeat(64));
  assert.equal(first.cfg.custom.keyHost, 'openrouter.ai');
  assert.ok(store.get('custom'));
  // The same address again without a key keeps it.
  const same = await setup.connectCustom(first.cfg, { baseUrl: 'https://openrouter.ai/api/v1', model: 'llama3.3' }, null);
  assert.equal(same.cfg.custom.keyHost, 'openrouter.ai');
  assert.ok(store.get('custom'));
  // Another address without a key: the old key is gone, not sent there.
  const other = await setup.connectCustom(same.cfg, { baseUrl: 'http://192.168.1.20:11434/v1', model: 'llama3.3' }, null);
  assert.equal(other.cfg.custom.keyHost, undefined);
  assert.equal(store.get('custom'), undefined);
});

test('Disconnect Other: its key and address gone; the ChatGPT plan answers if Other did', async () => {
  const { setup, store } = rig({ models: ['llama3.3'] });
  const on = await setup.connectCustom({}, { baseUrl: 'https://openrouter.ai/api/v1', model: 'llama3.3' }, 'sk-or-v1-' + 'd'.repeat(64));
  assert.equal(on.cfg.provider, 'custom');
  const off = await setup.disconnectCustom(on.cfg);
  assert.equal(off.cfg.custom, undefined);
  assert.equal(off.cfg.provider, 'chatgpt');
  assert.equal(store.get('custom'), undefined);
  const list = await setup.list(off.cfg);
  assert.equal(list.find(x => x.id === 'custom').ready, false);
});

// Choosing the AI in the desktop app (docs/milestone-3.md): every AI the core can talk to, each set
// up its own way, and the one the link uses.
//   - The ChatGPT plan: the browser sign-in (main.mjs, core/ai/signin).
//   - Anthropic, OpenAI, xAI, Google: an API key. Paste key reads the clipboard in the app (never the
//     window), tells the AI from the key's shape (providers/keytext.mjs), tests it with a live call
//     (the models list), and only then keeps it in the OS credential store.
//   - Other: any OpenAI-compatible address (OpenRouter, Groq, Ollama, LM Studio…), with a model and
//     an optional key, tested the same way.
// Nothing here logs a key; a result never carries one.
//
//   createAISetup({ manifests, keystore, signInFor, fetchFor }) → {
//     list(cfg) → [{ id, card, maker, kind, ready, current, keyExample, keysUrl }]
//     pasteKey(cfg, text) → { ok, cfg, id, card } | { ok: false, error, detail }
//     removeKey(cfg, id) → { ok }
//     connectCustom(cfg, { baseUrl, model }, keyText|null) → { ok, cfg } | { ok: false, error, detail, models? }
//     choose(cfg, id) → { ok, cfg } | { ok: false, error }
//   }
import { createProvider, customManifest, checkCustomUrl, CUSTOM_MODEL_RE, modelAvailable, isSignIn, userLine } from '../ai/providers/index.mjs';
import { pasteShape } from '../ai/providers/keytext.mjs';

const kindOf = (m) => (m.custom ? 'custom' : isSignIn(m) ? 'signin' : 'key');

/** The settings for a new AI: its own model and thinking unless the old ones are its too. */
function switchTo(cfg, m) {
  const next = { ...cfg, provider: m.id };
  const listed = (m.models?.list || []).some(x => x.id === next.model);
  if (!listed && !m.models?.allowAny) delete next.model;
  if (m.custom) delete next.model;
  const model = next.model || m.models?.default;
  if (next.effort && !Object.keys(m.effort?.[model] || {}).includes(next.effort)) delete next.effort;
  return next;
}

export function createAISetup({ manifests, keystore, signInFor = () => null, fetchFor = () => globalThis.fetch } = {}) {
  const byId = (id) => manifests.find(m => m.id === id) || null;
  const template = manifests.find(m => m.custom === true) || null;
  const errorWords = (m, e) => { const l = userLine(e, { provider: m?.name || 'your AI', product: 'Spellmind' }); return `${l.headline} ${l.detail}`.trim(); };

  // A live check: the models list, with this key (null for a server that takes none).
  async function test(m, key) {
    const provider = createProvider(m, { getKey: async () => key, fetch: fetchFor(m) });
    return provider.validate();
  }

  async function ready(m, cfg) {
    const kind = kindOf(m);
    try {
      if (kind === 'signin') { const s = signInFor(m); return s ? !!(await s.signedIn()) : false; }
      if (kind === 'custom') return !!(template && customManifest(template, cfg.custom));
      return !!(await keystore.get(m.id));
    } catch { return false; }
  }

  async function list(cfg = {}) {
    const current = cfg.provider || 'chatgpt';
    const out = [];
    for (const m of [...manifests].filter(x => !x.hidden).sort((a, b) => (a.display?.order ?? 99) - (b.display?.order ?? 99))) {
      out.push({
        id: m.id,
        card: m.display?.card || m.name,
        maker: m.display?.maker || null,
        kind: kindOf(m),
        ready: await ready(m, cfg),
        current: m.id === current,
        keyExample: m.keyExample || null,
        keysUrl: m.links?.keys || null,
        ...(m.custom && cfg.custom ? { custom: { baseUrl: cfg.custom.baseUrl, model: cfg.custom.model, ...(cfg.custom.keyHost ? { keyHost: cfg.custom.keyHost } : {}) } } : {}),
      });
    }
    return out;
  }

  async function pasteKey(cfg = {}, text) {
    const shape = pasteShape(text, manifests);
    if (!shape.key) {
      const detail = {
        clipboard_empty: 'Your clipboard is empty. Copy your API key first, then click Paste key.',
        not_a_key: 'What\'s on your clipboard isn\'t an API key. Copy the key itself from your AI\'s site.',
        subscription_token: 'That\'s a Claude sign-in token, which other apps can\'t use. Make an API key on Claude\'s console instead.',
        admin_key: 'That\'s an admin key, which can\'t send messages. Make a regular API key.',
        custom_key: 'That\'s an OpenRouter key: set it up under Other, with OpenRouter\'s address.',
      }[shape.reason] || 'That key isn\'t one Spellmind recognises.';
      return { ok: false, error: shape.reason || 'not_a_key', detail };
    }
    const m = byId(shape.id);
    if (!m || m.hidden) return { ok: false, error: 'unknown_ai', detail: 'That key is for an AI Spellmind doesn\'t offer.' };
    const v = await test(m, shape.key);
    if (!v.ok) return { ok: false, error: v.error?.kind || 'failed', detail: errorWords(m, v.error) };
    await keystore.set(m.id, shape.key);
    // The default model, if this key can use it; else the first listed one it can (the audit: a model
    // retired since the list was written answered every message with "This model was retired").
    const next = switchTo(cfg, m);
    const usable = (id) => !v.models?.length || modelAvailable(id, v.models);
    const model = next.model || m.models.default;
    if (!usable(model)) {
      const alt = m.models.list.find(x => !x.retiresAfter && usable(x.id));
      if (alt) next.model = alt.id;
    }
    return { ok: true, cfg: next, id: m.id, card: m.display?.card || m.name };
  }

  async function removeKey(cfg, id) {
    const m = byId(id);
    if (!m || kindOf(m) === 'signin') return { ok: false, error: 'not_a_key_ai' };
    await keystore.delete(id);
    return { ok: true };
  }

  async function connectCustom(cfg = {}, { baseUrl, model } = {}, keyText = null) {
    if (!template) return { ok: false, error: 'unsupported' };
    const c = checkCustomUrl(baseUrl);
    if (!c.ok) {
      const detail = {
        empty: 'Type the service\'s address (its base URL).',
        too_long: 'That address is too long.',
        bad_url: 'That isn\'t a web address.',
        not_http: 'The address starts with https:// (or http:// for this computer).',
        https_required: 'Use https:// for a service on the internet; http:// is only for this computer or your home network.',
        credentials: 'Leave the user name and password out of the address: paste the key instead.',
        query: 'Leave anything after ? or # out of the address.',
      }[c.error];
      return { ok: false, error: c.error, detail };
    }
    const id = typeof model === 'string' ? model.trim() : '';
    if (!CUSTOM_MODEL_RE.test(id)) return { ok: false, error: 'bad_model', detail: 'Type the model\'s name as the service writes it (like llama3.3 or openai/gpt-oss-120b).' };
    const m = customManifest(template, { baseUrl: c.baseUrl, model: id });
    if (!m) return { ok: false, error: 'bad_settings', detail: 'Those settings didn\'t make a working connection.' };
    // An optional key, from the clipboard: any key-looking text (services' keys have many shapes).
    let key = null;
    if (keyText != null) {
      key = String(keyText).trim();
      if (!key || key.length > 512 || /\s/.test(key)) return { ok: false, error: 'not_a_key', detail: 'What\'s on your clipboard isn\'t a key. Copy it again, or connect without one.' };
    }
    const v = await test(m, key);
    if (!v.ok) return { ok: false, error: v.error?.kind || 'failed', detail: errorWords(m, v.error) };
    // The model has to be one the service lists (when it lists any).
    if (v.models.length && !modelAvailable(id, v.models)) {
      // Only names shaped like model names, as the service sends them (the security review: any text, any length).
      const names = v.models.filter(x => typeof x === 'string' && CUSTOM_MODEL_RE.test(x));
      return { ok: false, error: 'model_not_found', detail: `The service doesn't list ${id}. It has: ${names.slice(0, 8).join(', ') || 'no models Spellmind can name'}${names.length > 8 ? '…' : ''}`, models: names.slice(0, 50) };
    }
    // The key belongs to the address it was given for (the security review: kept under "custom" alone,
    // it went to the next address typed in, in the clear over a home network's http). A new key is kept
    // with its host; a new host without one drops the old key.
    const oldHost = (() => { try { return cfg.custom?.baseUrl ? new URL(cfg.custom.baseUrl).host : null; } catch { return null; } })();
    const newHost = new URL(c.baseUrl).host;
    let keyHost = cfg.custom?.keyHost || null;
    if (key) { await keystore.set(m.id, key); keyHost = newHost; }
    else if (oldHost !== newHost || keyHost !== newHost) { await keystore.delete(m.id); keyHost = null; }
    return { ok: true, cfg: switchTo({ ...cfg, custom: { baseUrl: c.baseUrl, model: id, ...(keyHost ? { keyHost } : {}) } }, m) };
  }

  // Other, undone: its key gone, its address and model forgotten; the ChatGPT plan answers if Other did.
  async function disconnectCustom(cfg = {}) {
    await keystore.delete('custom');
    const next = { ...cfg };
    delete next.custom;
    if (next.provider === 'custom') { next.provider = 'chatgpt'; delete next.model; }
    return { ok: true, cfg: next };
  }

  async function choose(cfg = {}, id) {
    const m = byId(id);
    if (!m || m.hidden) return { ok: false, error: 'unknown_ai' };
    if (!(await ready(m, cfg))) return { ok: false, error: 'not_ready' };
    return { ok: true, cfg: switchTo(cfg, m.custom ? customManifest(template, cfg.custom) : m) };
  }

  return { list, pasteKey, removeKey, connectCustom, disconnectCustom, choose };
}

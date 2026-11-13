// One turn with the player's AI (docs/milestone-21.md, the audit's batch A): the request with its
// output ceiling and cache key, one retry for a busy AI, a reply cut at the ceiling said so, and the
// double-check (docs/milestone-17.md). Out of runner.mjs so a stand-in AI can test it.
//
//   createTurn({ m, model, label, provider, pack, log, effort, search }) → { ask, turn }
import crypto from 'node:crypto';
import { effortLevels, outputCeiling, thinkRoom, retryPlan } from '../ai/providers/index.mjs';
import { userLine } from '../ai/providers/errors.mjs';
import { buildRequest } from '../ai/context.mjs';
import { needsCheck, checkHistory, checkAsk, pickChecked } from '../ai/check.mjs';

export function createTurn({ m, model, label = model, provider, pack, log = () => {}, effort, search, retryMaxMs = 20000 }) {
  // The output ceiling of a request (the audit): the reply's own (the manifest's, 1,200 tokens) plus
  // room for its thinking level, held to the model's own maximum. Every AI here counts thinking inside
  // the ceiling, so at Medium or High a bare 1,200 could be all thinking: a reply cut, or none.
  const levels = effortLevels(m, model);
  const replyRoom = Number(m.limits?.maxOutputTokens) || 1200;
  const maxTokensFor = (e) => Math.min(outputCeiling(m, model), replyRoom + thinkRoom(levels.length ? e : null, m, model));
  // A chat's cache key (the ChatGPT plan's backend keeps a chat's prompt cached only when its requests
  // name the same session): a hash of the chat id, the same for its draft and its check.
  const cacheKeyFor = (chatId) => (chatId ? crypto.createHash('sha256').update(`spellmind:${chatId}`).digest('hex').slice(0, 32) : undefined);
  const words = (err) => {
    const l = userLine(err, { provider: m.name, model: label, product: 'Spellmind', final: true, thinking: levels.length > 0 });
    return `${l.headline} ${l.detail}`.trim();
  };
  const sleep = (ms, signal) => new Promise((done) => {
    const t = setTimeout(done, ms);
    signal?.addEventListener?.('abort', () => { clearTimeout(t); done(); }, { once: true });
  });

  // One request as it streamed: { text, finish } | { aborted } | { err, partial }.
  const once = async ({ system, messages, signal, effort: e, search: s, cacheKey }) => {
    let out = '', searched = false, finish = null;
    for await (const ev of provider.stream({ model, effort: e, system, messages, webSearch: s, maxTokens: maxTokensFor(e), cacheKey }, { signal })) {
      if (ev.type === 'text') out += ev.delta;
      else if (ev.type === 'done') finish = ev.finish || null;
      // What the request used, cached part included: whether a chat's prompt cache is reused shows here.
      else if (ev.type === 'usage' && ev.usage && !ev.usage.partial) log('usage', { input: ev.usage.input, cacheRead: ev.usage.cacheRead, cacheWrite: ev.usage.cacheWrite, output: ev.usage.output });
      else if (ev.type === 'progress' && ev.searching && !searched) { searched = true; log('web-search', {}); }
      else if (ev.type === 'error') {
        if (ev.error?.kind === 'interrupted') return { aborted: true };
        return { err: ev.error, partial: out };
      }
    }
    return { text: out, finish };
  };

  // One request: the text, or { aborted } or { error: { kind, text } }. A busy or rate-limited AI is
  // tried once more after its wait (at most 20 s) when nothing came yet; the words then say what's
  // true (the audit: "Trying again shortly…" was promised and never done). A reply cut at the ceiling
  // says so; one with no text, or a refusal with none, is an error the player can act on.
  const ask = async ({ history, userText, game, signal, effort: e, search: s, chatId }) => {
    const { system, messages, meta } = buildRequest({ pack, game, history, userText, search: !!s });
    log('request', { pack: pack.version, dataChars: meta.dataChars, omitted: meta.omitted.length ? meta.omitted : undefined, stale: game?.stale || undefined });
    const cacheKey = cacheKeyFor(chatId);
    for (let attempt = 0; ; attempt++) {
      const r = await once({ system, messages, signal, effort: e, search: s, cacheKey });
      if (r.aborted) return r;
      if (r.err) {
        const plan = !r.partial ? retryPlan(r.err, attempt, { maxRetries: 1, maxWaitMs: retryMaxMs }) : { retry: false };
        if (plan.retry) {
          log('retry', { kind: r.err.kind, ms: plan.delayMs });
          await sleep(plan.delayMs, signal);
          if (signal?.aborted) return { aborted: true };
          continue;
        }
        return { error: { kind: r.err.kind || 'error', text: words(r.err) } };
      }
      const text = r.text || '';
      if (!text.trim()) {
        const kind = r.finish === 'refusal' || r.finish === 'content_filter' ? 'content_blocked' : 'empty_reply';
        log('reply-empty', { finish: r.finish });
        return { error: { kind, text: words({ kind, provider: m.id }) } };
      }
      if (r.finish === 'length') {
        log('reply-cut', {});
        return { text: `${text.trimEnd()}\n\n(Cut short: ask "go on" for the rest.)` };
      }
      return { text };
    }
  };
  // A turn: the answer, then (docs/milestone-17.md) a double-check of one that names places, people,
  // routes, items or quest steps, unless the player turned it off. A failed check keeps the draft.
  const turn = async ({ chatId, text, history, signal, game, effort: pickedEffort, search: pickedSearch, check }) => {
    const e = pickedEffort || effort, s = pickedSearch ?? search;
    const draft = await ask({ history, userText: text, game, signal, effort: e, search: s, chatId });
    if (!draft.text || check === false || !needsCheck(text, draft.text)) return draft;
    log('check', {});
    const checked = await ask({ history: checkHistory(history, text, draft.text), userText: checkAsk(!!s), game, signal, effort: e, search: s, chatId });
    if (checked.aborted) return checked;
    if (!checked.text?.trim()) { log('check-failed', { kind: checked.error?.kind }); return draft; }
    // A check that came back as a comment, much shorter, or without its "Next:" line doesn't replace a good draft.
    const chosen = pickChecked(draft.text, checked.text);
    log('check-done', { used: chosen.used, why: chosen.why });
    return { text: chosen.text };
  };
  return { ask, turn, maxTokensFor };
}

// The link's service: what the addon draws on the strip comes in (handlePayload), messages go to the
// player's AI, and replies go back out in the slot addons with a push doorbell. Spellmind's own, a
// small rewrite of NeverQuestAlone's bridge/service.mjs (MIT; see NOTICE.md) on the same protocol (v2,
// NeverQuestAlone's docs/PROTOCOL.md §2–§4) and its store, publisher and doorbells, without its map,
// companion, check-ins, game gate, reload mode, patch day or guards.
//
//   createService({ addonsDir, stateDir, turn, log, now, slotCount, … })
//     → { start(), stop(), handlePayload(text), state, stats(), flushNow(), reRing() }
//
// turn({ chatId, text, history, signal, game }) runs one AI turn and resolves to { text } or
// { error: { kind, text } } (tools/spellmind.mjs builds it from core/ai). game is
// { state: { char, stats, talents, gear, bags, skills, quests, rep } | null, stale }: the character's
// parts the token holds (charstate.mjs); state is null for a message that carried no st= (no game
// data). The service never throws out of handlePayload: a record that can't be handled is logged and
// the rest go on.
//
// The character's state (docs/milestone-4.md): `state` records are handled before the payload's
// messages, so a message and its parts drawn in one frame meet. Each part is merged (a new sid
// starts over; a part is kept only when its seq is higher), persisted to stateDir/charstate.json and
// confirmed in the slot (bridge.state = { sid, parts = { char = 41, … } }), rung with the next ack. A
// message whose st= names parts not held yet is acked at once with a ring (the strip frees for the
// parts), then waits up to STATE_WAIT_MS for them, then runs with stale: true. The log has part
// names and sizes, never their contents.
//
// The rules kept from NeverQuestAlone, each for a reason:
// - A message is in the outbox (on disk) before it's acked; the addon redraws it until it's acked, so
//   copies are normal: keyed records are deduped by (token, key) for 7 days, and a duplicate is acked
//   again (§2.5).
// - A hello's answer is bridge.nonce in the next slot, rung once per nonce (§2.4).
// - The ack that starts a turn rings within ACK_RING_MS or with the turn's own ringing publish, so a
//   turn costs the addon one slot load, not two (PF-02).
// - A ring the addon didn't report reading (seen p=) is rung again every 10 s six times, then every
//   60 s, for 10 minutes (§3).
// - An alive beat every 10 s says the app is there.
import fs from 'node:fs';
import path from 'node:path';
import { parsePayload } from './records.mjs';
import { openStore } from './store.mjs';
import { createSignals } from './signals.mjs';
import { createPublisher } from './publisher.mjs';
import { SLOT_COUNT } from './slots.mjs';
import { renderReply, systemLine } from './render.mjs';
import { createRunQueue } from '../ai/runqueue.mjs';
import { looksLikeKey } from '../ai/security/keycheck.mjs';
import { writeFileQuick } from '../files.mjs';
import { readStateRecord, mergeInto, stReady, partSeqs, gameState, loadCharState, saveCharState, SID_RE } from './charstate.mjs';

/** The service's version: the addon's and this one's major numbers must match (the addon checks). */
export const SERVICE_VERSION = '0.1.0';
export const AGENT = Object.freeze({ id: 'main', name: 'Spellmind' });
export const ACKED_KEEP = 50;
export const ACK_RING_MS = 8000;
export const RERING_FAST_MS = 10000;
export const RERING_FAST_COUNT = 6;
export const RERING_SLOW_MS = 60000;
export const RERING_FOR_MS = 600000;
export const ALIVE_EVERY_MS = 10000;
/** How many earlier messages (user and assistant) go with a turn. */
export const HISTORY_MAX = 20;
export const RESERVED_PREFIX = /^\s*\[Spellmind/i;
/** How long a message waits for the parts its st= names before it runs with stale: true. */
export const STATE_WAIT_MS = 4000;
/** What the service tells the addon it takes (bridge.caps): state records, and z=1 bodies. */
export const CAPS = Object.freeze(['state', 'z']);
export const KEY_REFUSED = 'Not sent: that looks like an API key. Keys go in the Spellmind app, never in game.';

const isObj = v => !!v && typeof v === 'object' && !Array.isArray(v);

export function createService({ addonsDir, stateDir, turn, log = () => {}, now = Date.now, slotCount = SLOT_COUNT,
  concurrency = 2, ackRingMs = ACK_RING_MS, timers = true, publisherOpts = {}, stateWaitMs = STATE_WAIT_MS } = {}) {
  if (!addonsDir || !stateDir) throw new Error('createService needs addonsDir and stateDir');
  if (typeof turn !== 'function') throw new Error('createService needs turn()');
  fs.mkdirSync(stateDir, { recursive: true, mode: 0o700 });
  const store = openStore(stateDir, { log, now });
  const S = store.state;
  const signals = createSignals(addonsDir, { log });
  const queue = createRunQueue({ concurrency });
  let rering = { push: -1, count: 0, next: 0 };
  let intervals = [];
  let stopped = false;

  // ---- the character's state per token (charstate.json in the state folder)
  const chars = loadCharState(stateDir);
  const saveChars = () => { try { saveCharState(stateDir, chars); } catch (e) { log('charstate-write-failed', { code: e?.code ?? 'error' }); } };
  const waiting = new Map(); // outbox items waiting for their st= parts: `${token}:${key}` → { item, timer }

  // ---- the chats' history (what goes with a turn): chats.json in the state folder
  const historyFile = path.join(stateDir, 'chats.json');
  let history = {};
  try { const h = JSON.parse(fs.readFileSync(historyFile, 'utf8')); if (isObj(h)) history = h; } catch { history = {}; }
  const saveHistory = () => { try { writeFileQuick(historyFile, JSON.stringify(history)); } catch (e) { log('history-write-failed', { code: e?.code ?? 'error' }); } };
  function remember(chatId, role, content) {
    const h = Array.isArray(history[chatId]) ? history[chatId] : [];
    h.push({ role, content: String(content).slice(0, 12000) });
    history[chatId] = h.slice(-HISTORY_MAX);
    saveHistory();
  }

  // ---- the slot the addon reads (§4.1)
  function buildSlot() {
    const token = S.lastToken;
    const t = token ? S.tokens[token] : null;
    const chats = Object.values(S.chats).filter(c => !token || c.token === token).map((c) => {
      const waiting = store.outbox.some(o => o.chat === c.id);
      const running = Object.values(S.inflight).some(r => r.chat === c.id);
      return { id: c.id, agent: c.agent, label: '', busy: waiting || running || queue.busy?.(c.id) === true, queued: 0 };
    });
    return {
      v: 2, ts: new Date(now()).toISOString(), now: Math.floor(now() / 1000), token: token || '',
      bridge: { ver: SERVICE_VERSION, push: S.push, epoch: S.epoch, nonce: t?.nonce || '', acked: t?.acked || [], caps: [...CAPS], state: slotState(token) },
      gw: { state: 'ready', since: Math.floor((S.startedAt || now()) / 1000), queued: store.outbox.length },
      agents: [AGENT],
      chats,
      records: token ? store.recordsFor(token) : [],
    };
  }
  // bridge.state: the token's current sid and the seq of each part held (absent with none).
  function slotState(token) {
    const c = token ? chars.tokens[token] : null;
    return c ? { sid: c.sid, parts: partSeqs(c) } : undefined;
  }
  const publisher = createPublisher({ store, signals, addonsDir, buildSlot, log, slotCount, now, ...publisherOpts });

  function record(rec, { push = true } = {}) {
    const r = store.addRecord(rec, now());
    publisher.publish({ push });
    return r;
  }

  // ---- tokens, chats, acks
  function ensureToken(token) {
    let t = S.tokens[token];
    if (!t) {
      // A new token starts at the current head (§2.4 hello).
      t = S.tokens[token] = { nonce: '', nonces: [], startSeq: S.seq, lastReported: S.seq, maxReported: S.seq, ctx: null,
        sendCounter: 0, acked: [], readPush: S.push, firstSeen: now(), lastSeen: now() };
      log('token-new', { token });
    }
    t.lastSeen = now();
    return t;
  }
  function ensureChat(chatId, token) {
    let c = S.chats[chatId];
    if (!c) c = S.chats[chatId] = { id: chatId, agent: AGENT.id, label: '', created: now(), token };
    c.token = token;
    c.seen = now();
    return c;
  }
  function noteAck(token, key, { soon = false } = {}) {
    const t = S.tokens[token];
    if (!t) return;
    const had = (t.acked || []).includes(key);
    t.acked = [...(t.acked || []).filter(k => k !== key), key].slice(-ACKED_KEEP);
    if (had) return;
    if (soon) publisher.pushWithin(ackRingMs);
    else publisher.publish({ push: true });
  }
  function notePushRead(t, p) {
    const n = Number(p);
    if (!Number.isInteger(n) || n < 0) return;
    store.catchUp({ push: n });
    if (n <= (t.readPush || 0)) return;
    t.readPush = Math.min(n, S.push);
    store.saveState();
  }

  // ---- records in
  function handlePayload(text) {
    const { records, rejected } = parsePayload(text);
    for (const r of rejected) {
      log('record-rejected', { reason: r.reason, key: r.key || null });
      if (r.token && r.key) noteAck(r.token, r.key); // else the addon would draw it for good
    }
    // State before messages: a message and its parts drawn in one frame meet (otherwise in order).
    const ordered = [...records.filter(r => r.type === 'state'), ...records.filter(r => r.type !== 'state')];
    for (const r of ordered) {
      try { handleRecord(r); } catch (e) { log('record-error', { type: r.type, key: r.key || null, error: String(e?.message || e).slice(0, 120) }); }
    }
  }

  function handleRecord(r) {
    const t = ensureToken(r.token);
    if (S.lastToken !== r.token) { S.lastToken = r.token; store.saveState(); }
    const cursorMoved = store.reportCursor(r.token, r.args.cur);
    if (r.args.p !== undefined) notePushRead(t, r.args.p);
    if (r.type === 'hello') return onHello(r, t);
    if (r.type === 'seen') { if (cursorMoved) { store.saveState(); publisher.publish({}); } return; }
    if (r.type === 'state') return onState(r);
    if (!store.firstTime(r.token, r.key, now())) {
      noteAck(r.token, r.key);
      if (cursorMoved) publisher.publish({});
      return;
    }
    if (r.type === 'msg') return onMsg(r, t);
    if (r.type === 'stop') return onStop(r);
    // patch, forget, evt, upd: not Spellmind's yet; acked so the addon stops drawing them.
    noteAck(r.token, r.key);
    store.saveState();
  }

  function onHello(r, t) {
    const first = t.nonce !== r.nonce;
    t.nonce = r.nonce;
    if (first) t.nonces = [...(t.nonces || []).filter(n => n !== r.nonce), r.nonce].slice(-3);
    t.ver = r.args.ver; t.build = r.args.build; t.iface = r.args.iface; t.sig = r.args.sig; t.slots = Number(r.args.slots) || null;
    t.helloAt = now();
    // The hello's sid (new at each login, kept over a /reload): parts held from another sid go.
    const held = chars.tokens[r.token];
    if (SID_RE.test(r.args.sid || '') && held && held.sid !== r.args.sid) {
      chars.tokens[r.token] = { sid: r.args.sid, parts: {} };
      saveChars();
      log('state-session', { token: r.token, sid: r.args.sid });
    }
    t.sendCounter = Math.max(t.sendCounter || 0, Number(r.args.n) || 0);
    S.lastToken = r.token;
    if (t.ver && String(t.ver).split('.')[0] !== SERVICE_VERSION.split('.')[0]) log('version-warn', { addon: t.ver, service: SERVICE_VERSION });
    store.saveState();
    if (first) log('hello', { token: r.token, nonce: r.nonce, ver: t.ver, build: t.build, sig: t.sig, slots: t.slots });
    publisher.publish({ push: first });
  }

  function onState(r) {
    const s = readStateRecord(r.args, r.body);
    if (!s.ok) {
      const part = s.part ?? (/^[a-z]{1,12}$/.test(r.args.part || '') ? r.args.part : null);
      log('state-rejected', { token: r.token, part, reason: s.reason, bytes: Buffer.byteLength(String(r.body || '')) });
      return;
    }
    if (s.off) {
      if (!chars.tokens[r.token]) return;
      delete chars.tokens[r.token];
      saveChars();
      log('state-off', { token: r.token });
      publisher.pushWithin(ackRingMs);
      return;
    }
    const m = mergeInto(chars.tokens[r.token] || null, s);
    if (!m.changed) return; // older or the same seq: the slot confirms it already
    chars.tokens[r.token] = m.stored;
    saveChars();
    if (m.reset) log('state-session', { token: r.token, sid: s.sid });
    log('state', { token: r.token, part: s.part, seq: s.seq, bytes: s.bytes, z: s.z || undefined });
    publisher.pushWithin(ackRingMs);
    // Messages waiting for these parts go now.
    for (const [id, w] of [...waiting]) {
      if (w.item.token !== r.token || !stReady(w.item.st, chars.tokens[r.token])) continue;
      clearTimeout(w.timer);
      waiting.delete(id);
      send(w.item);
    }
  }

  function onMsg(r, t) {
    const text = String(r.text || '');
    if (RESERVED_PREFIX.test(text)) {
      noteAck(r.token, r.key);
      store.saveState();
      record({ t: 'error', chat: r.chat, kind: 'refused', text: systemLine('Not sent: messages can\'t start with "[Spellmind".') });
      log('msg-refused', { key: r.key, chat: r.chat, reason: 'reserved prefix' });
      return;
    }
    if (looksLikeKey(text)) {
      noteAck(r.token, r.key);
      store.saveState();
      record({ t: 'error', chat: r.chat, kind: 'refused', text: systemLine(KEY_REFUSED) });
      log('msg-refused', { key: r.key, chat: r.chat, reason: 'looks like an API key' });
      return;
    }
    const c = ensureChat(r.chat, r.token);
    // st: the parts the addon hadn't seen confirmed ('' = it had them all); none = no game data.
    const st = typeof r.args.st === 'string' ? r.args.st.slice(0, 200) : null;
    const item = { token: r.token, key: r.key, chat: c.id, kind: 'msg', text, st, firstSeen: now(), attempts: 0 };
    store.addOutbox(item); // on disk before the ack (SE-2)
    // A message that waits for its parts is acked with a ring now, so the strip frees for them.
    const wait = !!st && !stReady(st, chars.tokens[r.token]);
    noteAck(r.token, r.key, { soon: !wait });
    store.saveState();
    log('msg', { key: r.key, chat: c.id, bytes: Buffer.byteLength(text), game: st === null ? undefined : true, wait: wait || undefined });
    publisher.publish({});
    send(item);
  }

  function onStop(r) {
    noteAck(r.token, r.key);
    store.saveState();
    const c = S.chats[r.chat];
    if (!c) { publisher.publish({}); return; }
    const held = store.outbox.filter(o => o.chat === c.id && !o.running);
    for (const o of held) {
      const w = waiting.get(`${o.token}:${o.key}`);
      if (w) { clearTimeout(w.timer); waiting.delete(`${o.token}:${o.key}`); }
      store.removeOutbox(o.token, o.key);
      record({ t: 'aborted', chat: c.id, kind: 'user', text: systemLine('Stopped before it went to your AI.') }, { push: false });
    }
    queue.abort(c.id);
    log('stop', { chat: c.id, waiting: held.length });
    publisher.publish({ push: true });
  }

  // ---- turns
  // The game data a turn gets: none for a message without st=; else the token's parts, stale when
  // the ones st= names didn't come in time.
  function gameFor(item) {
    if (item.st === null || item.st === undefined) return { state: null, stale: false };
    const c = chars.tokens[item.token];
    return { state: gameState(c), stale: !stReady(item.st, c) };
  }

  function send(item) {
    const runId = `sm:${item.token}:${item.key}`; // the turn's idempotency key (§2.3)
    if (S.inflight[runId] || store.isRunPublished(runId)) return;
    // Its parts not here yet: it waits for them (onState sends it), or for stateWaitMs, then goes stale.
    const id = `${item.token}:${item.key}`;
    if (waiting.has(id)) return;
    if (item.st && !item.waited && !stReady(item.st, chars.tokens[item.token])) {
      const timer = setTimeout(() => {
        waiting.delete(id);
        if (stopped || !store.outbox.some(o => o.token === item.token && o.key === item.key)) return; // stopped meanwhile
        item.waited = true;
        log('state-wait-over', { key: item.key, chat: item.chat, ms: stateWaitMs });
        send(item);
      }, stateWaitMs);
      waiting.set(id, { item, timer });
      return;
    }
    S.inflight[runId] = { chat: item.chat, key: item.key, token: item.token, sentAt: now(), kind: 'msg' };
    store.saveState();
    // A copy: the turn's history is what was said before it, whatever the chat says meanwhile.
    const prior = Array.isArray(history[item.chat]) ? history[item.chat].map(m => ({ ...m })) : [];
    queue.run(item.chat, async (signal) => {
      const o = store.outbox.find(x => x.token === item.token && x.key === item.key);
      if (o) o.running = true;
      const game = gameFor(item);
      if (item.st !== null && item.st !== undefined) log('turn-game', { chat: item.chat, parts: game.state ? Object.keys(game.state) : [], stale: game.stale || undefined });
      return turn({ chatId: item.chat, text: item.text, history: prior, signal, game });
    }).then((res) => finish(runId, item, res), (err) => finish(runId, item, err?.name === 'AbortError' ? { aborted: true } : { error: { kind: 'error', text: String(err?.message || err) } }));
  }

  function finish(runId, item, res) {
    if (stopped) return;
    delete S.inflight[runId];
    store.removeOutbox(item.token, item.key);
    const c = S.chats[item.chat] || ensureChat(item.chat, item.token);
    if (res?.aborted) {
      record({ t: 'aborted', chat: c.id, kind: 'user', text: systemLine('Stopped.') });
      log('turn-aborted', { chat: c.id });
      return;
    }
    if (res?.error) {
      const rec = record({ t: 'error', chat: c.id, kind: String(res.error.kind || 'error').slice(0, 32), text: systemLine(res.error.text || 'Something went wrong.') });
      store.markRun(runId, rec.seq);
      store.saveState();
      log('turn-error', { chat: c.id, kind: res.error.kind });
      return;
    }
    const raw = String(res?.text ?? '');
    if (!raw.trim()) {
      record({ t: 'error', chat: c.id, kind: 'empty', text: systemLine('Your AI sent an empty reply. Ask again.') });
      return;
    }
    const r = renderReply(raw);
    const rec = store.addRecord({ t: 'reply', chat: c.id, run: runId, agent: AGENT.id, text: r.text, summary: r.summary, more: r.more }, now());
    store.markRun(runId, rec.seq);
    store.saveState();
    remember(c.id, 'user', item.text);
    remember(c.id, 'assistant', raw);
    log('reply', { chat: c.id, seq: rec.seq, chars: raw.length, more: r.more || undefined });
    publisher.publish({ push: true });
  }

  // ---- doorbells
  function reRing() {
    const t = S.lastToken ? S.tokens[S.lastToken] : null;
    const P = publisher.settledPush();
    if (!t || (t.readPush || 0) >= P) return;
    const at = S.pushAt || 0;
    if (now() - at > RERING_FOR_MS) return;
    if (rering.push !== P) rering = { push: P, count: 0, next: at + RERING_FAST_MS };
    if (now() < rering.next) return;
    rering.count += 1;
    rering.next = now() + (rering.count < RERING_FAST_COUNT ? RERING_FAST_MS : RERING_SLOW_MS);
    signals.ringPush();
    log('rering', { push: P, read: t.readPush || 0, count: rering.count });
  }

  return {
    get state() { return S; },
    /** The character's state per token: { tokens: { token: { sid, parts: { name: { seq, value } } } } }. */
    get charState() { return chars; },
    store,
    publisher,
    handlePayload,
    reRing,
    flushNow: () => publisher.flushNow(),
    stats: () => ({ tokens: Object.keys(S.tokens).length, chats: Object.keys(S.chats).length, outbox: store.outbox.length, seq: S.seq, push: S.push, publisher: publisher.stats() }),
    start() {
      S.startedAt = now();
      signals.ensure(); // the bells the addon probes for, made before anything rings
      store.saveState();
      publisher.publish({}); // a slot for an addon that loads before anything is said
      // Messages taken before a restart and never answered go again (their runs are new: the old process is gone).
      for (const k of Object.keys(S.inflight)) delete S.inflight[k];
      for (const o of store.outbox) { o.running = false; send(o); }
      if (timers) {
        signals.beat();
        intervals.push(setInterval(() => signals.beat(), ALIVE_EVERY_MS));
        intervals.push(setInterval(reRing, 2000));
      }
      log('service-started', { version: SERVICE_VERSION, slots: slotCount, outbox: store.outbox.length });
    },
    stop() {
      stopped = true;
      for (const i of intervals) clearInterval(i);
      intervals = [];
      for (const w of waiting.values()) clearTimeout(w.timer);
      waiting.clear();
      queue.abortAll?.();
      try { publisher.stop(); } catch { /* stopping */ }
      try { signals.stop(); } catch { /* stopping */ }
      store.saveState();
      store.flush?.();
    },
  };
}

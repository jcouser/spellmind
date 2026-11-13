// Spellmind: adapted from NeverQuestAlone's tests/nqa_addon_test.js (MIT; see NOTICE.md).
// The Spellmind addon (addon/Spellmind) in a fengari VM on the WoW stub (tests/helpers/addon-vm.mjs),
// against protocol v2 and the bridge's own code: what it draws is found and decoded by
// core/link/strip.mjs at Spellmind's spot (272 px down) and parsed by core/link/records.mjs; a slot
// written by core/link/luaenc.mjs applies; doorbells load slots; the outbox survives /reload; keys
// are refused; and a whole turn runs through the real service (core/link/service.mjs).
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { newVM, reloadVM } from '../helpers/addon-vm.mjs';
import { findAndDecode } from '../../core/link/strip.mjs';
import { parsePayload } from '../../core/link/records.mjs';
import { slotTable } from '../../core/link/luaenc.mjs';
import { createService } from '../../core/link/service.mjs';

const KEY = 'sk-ant-api03-' + 'Ab3dEf9hIj'.repeat(4);

// After login the hello goes up at 3 s, and the 2-second poll has armed the doorbells.
function session(opts = {}) {
  return newVM(opts).login().advance(3.1);
}

// What the capture reads off the screen: the records on the strip (null: no strip).
function stripRecords(vm) {
  const img = vm.screen();
  if (!img) return null;
  const r = findAndDecode(img);
  assert.equal(r.kind, 'decoded', `strip ${r.kind} ${r.reason || ''}`);
  assert.deepEqual([r.geometry.x0, r.geometry.y0, r.geometry.pitch], [0, 0, 3], "Spellmind's spot: the top-left corner (NeverQuestAlone not loaded), 3 px cells");
  const { records, rejected } = parsePayload(r.text);
  assert.equal(rejected.length, 0, JSON.stringify(rejected));
  return records;
}

// A doorbell pulse (PROTOCOL §3): the bell reads missing for one poll, then present again.
// Push rings take turns on the two bells, as the app's do.
function ring(vm, bell = null) {
  if (!bell) bell = vm.pushBell = vm.pushBell === 'push_a' ? 'push_b' : 'push_a';
  vm.run('NS.Link.Poll()');
  vm.bell(`bell_${bell}`, false).run('NS.Link.Poll()');
  vm.bell(`bell_${bell}`, true).run('NS.Link.Poll()');
  return vm;
}

// A slot file as the app writes it (luaenc slotTable), for this session's token unless given.
function slotFor(vm, { push = 1, acked = [], records = [], nonce = vm.evaluate('NS.R.nonce'), token = vm.evaluate('SpellmindDB.token'), v = 2, ver = '0.1.0' } = {}) {
  const slot = { ts: '2026-11-10T12:00:00Z', now: vm.num('time()'), token, bridge: { ver, push, nonce, acked, caps: [] },
    gw: { state: 'ready', since: 0, queued: 0 }, agents: [{ id: 'main', name: 'Spellmind' }], chats: [], records };
  const text = slotTable('SpellmindSlotData', slot).text;
  return v === 2 ? text : text.replace('v = 2,', `v = ${v},`);
}

test('/sm hello puts a msg record on the strip, 272 px down, with the hello beside it; the app not heard yet is said', () => {
  const vm = session();
  const before = stripRecords(vm);
  assert.deepEqual(before.map(r => r.type), ['hello']);
  const h = before[0];
  const { sid, ...rest } = h.args;
  assert.deepEqual(rest, { cur: '0', ver: '0.1.0', build: '70009', iface: '16001', n: '0', ctx: '0', sig: 'ok', slots: '200', slot: '1', mode: 'pixel' });
  assert.match(sid, /^[0-9a-f]{16}$/, 'the character session id (milestone 4)');
  assert.deepEqual(Object.keys(h.args).slice(-1), ['sid'], 'last');
  assert.equal(h.key, vm.evaluate('NS.R.nonce'));
  vm.slash('hello');
  const recs = stripRecords(vm);
  assert.deepEqual(recs.map(r => r.type), ['msg', 'hello'], 'newest first');
  const m = recs[0];
  assert.equal(m.token, vm.evaluate('SpellmindDB.token'));
  assert.equal(m.key, `${vm.evaluate('NS.R.nonce')}_1`);
  assert.equal(m.chat, vm.evaluate('SpellmindDB.chat'));
  assert.deepEqual(m.args, { cur: '0', agent: 'main', ctx: '0' });
  assert.equal(m.text, 'hello');
  assert.deepEqual(vm.outbox().map(e => e.key), [m.key]);
  assert.ok(vm.chatLines().includes('Spellmind: Start the Spellmind app to get answers.'));
  assert.equal(vm.evaluate('NS.Link.Status()'), 'Start the Spellmind app to get answers.');
  assert.deepEqual(vm.json('STUB.forbidden'), {});
});

test('the strip ignores its parent\'s scale and takes 768 / the physical height, at the top-left of UIParent; a display change rescales it', () => {
  const vm = session();
  const f = vm.json('{ scale = SpellmindStrip.scale, ignore = SpellmindStrip.ignoreParentScale, x = SpellmindStrip.x, y = SpellmindStrip.y, point = SpellmindStrip.anchor.point, rel = SpellmindStrip.anchor.rel == UIParent, relPoint = SpellmindStrip.anchor.relPoint, strata = SpellmindStrip.strata }');
  assert.deepEqual(f, { scale: 768 / 1080, ignore: true, x: 0, y: 0, point: 'TOPLEFT', rel: true, relPoint: 'TOPLEFT', strata: 'TOOLTIP' });
  vm.run('STUB.physH = 1440; STUB.FireEvent("DISPLAY_SIZE_CHANGED")');
  assert.equal(vm.json('SpellmindStrip.scale'), 768 / 1440);
  vm.run('STUB.physH = 2160; STUB.FireEvent("UI_SCALE_CHANGED")');
  assert.equal(vm.json('SpellmindStrip.scale'), 768 / 2160);
  assert.ok(stripRecords(vm), 'still read at 272 physical px');
});

test('a slot written by slotTable(\'SpellmindSlotData\') and loaded on a push ring acks the message and delivers the reply into the window and the chat frame', () => {
  const vm = session();
  vm.slash('Which profession for a rogue?');
  const [{ key }] = vm.outbox();
  const chat = vm.evaluate('SpellmindDB.chat');
  vm.slotText(slotFor(vm, { push: 1, acked: [key], records: [
    { seq: 1, t: 'reply', chat, mid: 'm1', agent: 'main', text: 'Take **Skinning** ||cff00ff00 always||r.\nA |Hitem:2140|h link stays text.', summary: 'Take Skinning.', more: 0 },
    { seq: 2, t: 'reply', chat: 'c0ffee1', mid: 'm2', agent: 'main', text: 'not ours', summary: '', more: 0 },
  ] }));
  ring(vm);
  assert.deepEqual(vm.loads(), ['Spellmind_S001']);
  assert.deepEqual(vm.outbox(), [], 'acked');
  assert.equal(vm.num('SpellmindDB.cursor'), 2);
  assert.equal(vm.num('NS.R.orphans'), 1, 'another chat\'s record makes nothing');
  // A short reply shows whole in the chat frame, line by line, its escapes kept inert.
  assert.ok(vm.chatLines().includes('Spellmind: Take **Skinning** ||cff00ff00 always||r.'), JSON.stringify(vm.chatLines()));
  assert.ok(vm.chatLines().includes('   A ||Hitem:2140||h link stays text.'), JSON.stringify(vm.chatLines()));
  const lines = vm.savedLines();
  assert.ok(lines.includes('|cff9d7dffSpellmind:|r Take **Skinning** ||cff00ff00 always||r.'), JSON.stringify(lines));
  assert.ok(lines.includes('A ||Hitem:2140||h link stays text.'), 'a single | is doubled: no live link');
  vm.slash('');
  assert.ok(vm.bool('SpellmindWindow.shown'), '/sm alone opens the window');
  // The window draws the conversation as messages (milestone 6): the question, then the whole reply.
  const shown = vm.windowLines();
  assert.equal(shown.at(-1), 'Take **Skinning** ||cff00ff00 always||r.\nA ||Hitem:2140||h link stays text.', JSON.stringify(shown));
  assert.equal(vm.evaluate('SpellmindWindow.status.text'), 'Connected', 'heard and nothing awaited');
  vm.slash('');
  assert.equal(vm.bool('SpellmindWindow.shown'), false, 'and closes it');
  // The load is reported: a seen with the cursor, the push counter read and the next slot.
  const seen = stripRecords(vm);
  assert.deepEqual(seen.map(r => r.type), ['seen']);
  assert.deepEqual(seen[0].args, { cur: '2', p: '1', slot: '2' });
  vm.advance(4.5);
  assert.equal(vm.bool('SpellmindStrip.shown'), true, 'up for 5 s');
  vm.advance(0.8); // the next 0.25 s tick after its 5 s
  assert.equal(vm.bool('SpellmindStrip.shown'), false, 'nothing left to draw');
});

test('error and aborted records show too; a replayed reply shows in the window only; a slot for another token or protocol applies nothing', () => {
  const vm = session();
  vm.slash('one');
  const chat = vm.evaluate('SpellmindDB.chat');
  vm.slotText(slotFor(vm, { token: 'ffffffff', records: [{ seq: 1, t: 'reply', chat, text: 'wrong token', summary: '', more: 0 }] }));
  ring(vm);
  assert.equal(vm.num('SpellmindDB.cursor'), 0);
  assert.equal(vm.outbox().length, 1);
  vm.advance(1.6);
  vm.slotText(slotFor(vm, { v: 3, records: [{ seq: 1, t: 'reply', chat, text: 'wrong protocol', summary: '', more: 0 }] }));
  ring(vm);
  assert.equal(vm.num('SpellmindDB.cursor'), 0);
  assert.ok(vm.chatLines().some(l => l.includes("can't read what the Spellmind app sends")));
  vm.advance(1.6);
  vm.slotText(slotFor(vm, { push: 2, records: [
    { seq: 1, t: 'reply', chat, text: 'old answer', summary: 'old', more: 0, replay: 1 },
    { seq: 2, t: 'error', chat, kind: 'overloaded', text: 'Your AI is busy | try again.' },
    { seq: 3, t: 'aborted', chat, kind: 'user', text: '' },
  ] }));
  ring(vm);
  assert.equal(vm.num('SpellmindDB.cursor'), 3);
  const lines = vm.savedLines();
  assert.ok(lines.includes('|cff9d7dffSpellmind:|r old answer'));
  assert.ok(lines.includes('|cffff6060Spellmind:|r Your AI is busy || try again.'));
  assert.ok(lines.includes('|cff9d7dffSpellmind:|r Stopped.'));
  const chatLines = vm.chatLines();
  assert.ok(!chatLines.some(l => l.includes('old')), 'a replay isn\'t news');
  assert.ok(chatLines.includes('Spellmind: Your AI is busy || try again.'));
  assert.ok(chatLines.includes('Spellmind: Stopped.'));
});

test('a doorbell flip (push bell present, then missing) loads one slot; with present.wav missing too, nothing counts', () => {
  const vm = session();
  vm.slotText(slotFor(vm, { push: 1 }));
  assert.deepEqual(vm.loads(), []);
  vm.run('NS.Link.Poll()');
  assert.deepEqual(vm.loads(), [], 'armed, not rung');
  vm.bell('bell_push_b', false).run('NS.Link.Poll()');
  assert.deepEqual(vm.loads(), ['Spellmind_S001'], 'the flip loads the next slot');
  assert.equal(vm.bool('NS.R.helloAnswered'), true);
  assert.equal(vm.evaluate('NS.R.sig.live'), 'ok', 'a ring after the hello: the doorbells work');
  vm.bell('bell_push_b', true).run('NS.Link.Poll()');
  // A second ring right away waits for the 1.5 s gap, then loads the next slot.
  vm.bell('bell_push_a', false).run('NS.Link.Poll()');
  assert.equal(vm.loads().length, 1);
  vm.bell('bell_push_a', true).advance(1.3);
  assert.equal(vm.loads().length, 1, 'not before the gap');
  vm.advance(0.5); // the first 0.25 s tick past 1.5 s

  assert.deepEqual(vm.loads(), ['Spellmind_S001', 'Spellmind_S002']);
  // Sound off: every file reads missing, present.wav too: no ring is heard.
  vm.advance(2);
  vm.bell('present', false).bell('bell_push_a', false).bell('bell_push_b', false).run('NS.Link.Poll()');
  vm.advance(2);
  assert.equal(vm.loads().length, 2);
});

test('the outbox survives a /reload: the record is drawn again verbatim, with the same key, beside the new session\'s hello', () => {
  const vm = session();
  vm.slash('hello');
  const [saved] = vm.outbox();
  const before = stripRecords(vm).find(r => r.type === 'msg');
  const back = reloadVM(vm).login();
  assert.deepEqual(back.outbox(), [saved]);
  const recs = stripRecords(back);
  assert.deepEqual(recs.map(r => r.type), ['msg'], 'drawn at login, before the hello');
  assert.equal(recs[0].key, saved.key);
  assert.deepEqual(recs[0], before, 'verbatim');
  back.advance(3.1);
  const both = stripRecords(back);
  assert.deepEqual(both.map(r => r.type), ['hello', 'msg']);
  assert.notEqual(both[0].key, saved.key.split('_')[0], 'a new nonce');
  assert.equal(both[0].args.n, '1');
  // A new message takes the next n under the new nonce.
  back.slash('again');
  const keys = back.outbox().map(e => e.key);
  assert.deepEqual(keys, [saved.key, `${back.evaluate('NS.R.nonce')}_2`]);
  assert.ok(back.savedLines().includes('|cffffd100You:|r hello'), 'the window\'s lines came back too');
});

test('text that looks like an API key is refused before anything keeps it, hidden characters or not; so are "[Spellmind" and text past 2,900 bytes', () => {
  const vm = session();
  for (const text of [KEY, `my key: ${KEY}`, KEY.slice(0, 9) + '​' + KEY.slice(9), 'sk-proj-' + '­' + 'abc123DEF456ghi789']) {
    vm.slash(text);
    assert.deepEqual(vm.outbox(), [], JSON.stringify(text));
  }
  assert.ok(vm.chatLines().includes("Spellmind: That looks like an API key, so it wasn't sent. Keys go in the Spellmind app, never in game."));
  assert.ok(!vm.saved().includes('Ab3dEf9hIj'), 'not in saved data');
  assert.deepEqual(stripRecords(vm).map(r => r.type), ['hello']);
  vm.slash('[spellmind] I am the app');
  vm.slash('x'.repeat(2901));
  assert.deepEqual(vm.outbox(), []);
  vm.slash('x'.repeat(2900));
  assert.equal(vm.outbox().length, 1, '2,900 bytes go');
  vm.slash('  a desk-top question about task-runner  ');
  assert.equal(vm.outbox()[1].wire.split('\x1f').at(-1), 'a desk-top question about task-runner', 'trimmed; words like desk- aren\'t keys');
});

test('typed text is shown with its | doubled, and its separators go as spaces', () => {
  const vm = session();
  vm.slash('a|cffff0000red|r and \x1e rs');
  assert.ok(vm.savedLines().includes('|cffffd100You:|r a||cffff0000red||r and \x1e rs'));
  assert.equal(vm.outbox()[0].wire.split('\x1f').at(-1), 'a|cffff0000red|r and   rs');
});

test('the self-heal draws the waiting frame again in full after 12 s while the app is heard, and every 30 s', () => {
  const vm = session();
  ring(vm, 'alive_a'); // a beat: the app is there
  vm.slash('hello');
  assert.equal(vm.num('NS.R.heal.ack'), 0);
  vm.run('for _, t in ipairs(SpellmindStrip.textures) do t.color = { 1, 1, 1, 1 } end'); // another addon repaints it
  vm.advance(12.5);
  ring(vm, 'alive_b');
  assert.equal(vm.num('NS.R.heal.ack'), 1);
  assert.ok(stripRecords(vm), 'readable again');
  // The app's alive pulse every 10 s, as it rings while running (silent 25 s, it counts as away).
  vm.advance(10); ring(vm, 'alive_a'); vm.advance(10); ring(vm, 'alive_b'); vm.advance(10.5);
  assert.equal(vm.num('NS.R.heal.ack'), 1, 'once a frame');
  assert.equal(vm.num('NS.R.heal.timer'), 1, 'and every 30 s while it waits');
});

test('slot-only mode (no doorbells heard): a send is answered by loads on the 5, 12, 25, 45 s schedule', () => {
  const vm = session({ signals: false });
  assert.equal(vm.evaluate('NS.R.sig.static'), 'present-missing');
  vm.slash('hello');
  const chat = vm.evaluate('SpellmindDB.chat');
  const [{ key }] = vm.outbox();
  vm.slotText(slotFor(vm, { acked: [key], records: [{ seq: 1, t: 'reply', chat, text: 'Here.', summary: 'Here.', more: 0 }] }));
  vm.advance(5.2);
  assert.ok(vm.loads().length >= 1);
  assert.ok(vm.chatLines().includes('Spellmind: Here.'));
  vm.run('STUB.onLoadAddOn = nil');
  const n = vm.loads().length;
  vm.advance(60);
  assert.equal(vm.loads().length, n, 'nothing awaited: no more loads');
});

test('a whole turn through the real service: the strip read into handlePayload, the slot it writes loaded on a ring, the reply shown', async (t) => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'sm-addon-'));
  const addonsDir = path.join(root, 'AddOns');
  fs.mkdirSync(path.join(addonsDir, 'Spellmind', 'sig', 'ctl'), { recursive: true });
  for (let i = 1; i <= 3; i++) fs.mkdirSync(path.join(addonsDir, `Spellmind_S00${i}`), { recursive: true });
  const svc = createService({ addonsDir, stateDir: path.join(root, 'state'), slotCount: 3, timers: false, ackRingMs: 0,
    turn: async ({ text }) => ({ text: `**Echo:** ${text} | with a pipe.` }) });
  svc.start();
  t.after(() => { svc.stop(); fs.rmSync(root, { recursive: true, force: true }); });

  const vm = session();
  vm.slash('Where do I train?');
  const img = vm.screen();
  svc.handlePayload(findAndDecode(img).text);
  await new Promise(r => setTimeout(r, 30));
  svc.flushNow();
  vm.slotText(fs.readFileSync(path.join(addonsDir, 'Spellmind_S001', 'Inbox.lua'), 'utf8'));
  ring(vm);
  assert.deepEqual(vm.outbox(), [], 'acked');
  assert.equal(vm.bool('NS.R.helloAnswered'), true, 'hello answered');
  assert.ok(vm.chatLines().includes('Spellmind: Echo: Where do I train? || with a pipe.'), `the short reply whole in the chat frame: ${JSON.stringify(vm.chatLines())}`);
  assert.ok(vm.savedLines().includes('|cff9d7dffSpellmind:|r Echo: Where do I train? || with a pipe.'));
  // The seen that follows moves the service's cursor.
  svc.handlePayload(findAndDecode(vm.screen()).text);
  const token = vm.evaluate('SpellmindDB.token');
  assert.equal(svc.state.tokens[token].lastReported ?? svc.state.tokens[token].maxReported, vm.num('SpellmindDB.cursor'));
  // The inbox the service writes is read at the next login.
  const inbox = fs.readFileSync(path.join(addonsDir, 'Spellmind', 'Inbox.lua'), 'utf8');
  assert.match(inbox, /^SpellmindInbox = \{/m);
});

test('the window\'s box: Enter sends and leaves the box (so the movement keys move the character, not type), an empty Enter leaves it too', () => {
  const vm = session();
  vm.slash(''); // /sm opens the window, the box focused
  assert.equal(vm.evaluate('tostring(SpellmindWindow.input:HasFocus())'), 'true');
  vm.run('SpellmindWindow.input:SetText("which professions suit a rogue?")');
  vm.run('SpellmindWindow.input:GetScript("OnEnterPressed")(SpellmindWindow.input)');
  assert.equal(vm.evaluate('tostring(SpellmindWindow.input:HasFocus())'), 'false', 'Enter left the box');
  assert.equal(vm.evaluate('SpellmindWindow.input:GetText()'), '', 'sent, so emptied');
  assert.deepEqual(stripRecords(vm).filter(r => r.type === 'msg').map(r => r.text), ['which professions suit a rogue?']);
  vm.run('SpellmindWindow.input:SetFocus(); SpellmindWindow.input:SetText("   ")');
  vm.run('SpellmindWindow.input:GetScript("OnEnterPressed")(SpellmindWindow.input)');
  assert.equal(vm.evaluate('tostring(SpellmindWindow.input:HasFocus())'), 'false', 'an empty Enter leaves it too');
  assert.equal(stripRecords(vm).filter(r => r.type === 'msg').length, 1, 'and sends nothing');
});

test('/sm probe: every client function tried safely, the results saved in SpellmindDB.probe, nothing on the strip', () => {
  const vm = session();
  const before = stripRecords(vm).length;
  vm.slash('probe');
  assert.ok(vm.chatLines().some(l => /probed \d+ client functions/.test(l)));
  assert.equal(vm.evaluate('type(SpellmindDB.probe)'), 'table');
  assert.equal(vm.evaluate('type(SpellmindDB.probe["UnitClass(player)"])'), 'table');
  // Round 4 (features.md §5): the quest calls, the game windows and the loaded addons, by name only.
  assert.equal(vm.evaluate('type(SpellmindDB.probe.frames)'), 'table');
  assert.equal(vm.evaluate('type(SpellmindDB.probe.globals)'), 'table');
  assert.equal(vm.evaluate('type(SpellmindDB.probe["fns:C_QuestLog"])'), 'string');
  assert.equal(vm.evaluate('type(SpellmindDB.probe["C_QuestLog.GetQuestObjectives(" .. tostring(SpellmindDB.probe["first quest id"]):gsub("^number:", "") .. ")"])'), 'table');
  assert.equal(stripRecords(vm).length, before, 'nothing sent');
});

test('the chat frame: a short reply (4 lines at most) whole, so a list after "…three talents:" shows; a longer one its summary and where the rest is', () => {
  const vm = session();
  const key = vm.slash('what talents?');
  const chat = vm.evaluate('SpellmindDB.chat');
  vm.slotText(slotFor(vm, { push: 1, acked: [`${vm.evaluate('NS.R.nonce')}_1`], records: [
    { seq: 1, t: 'reply', chat, agent: 'main', text: 'You have 5 points across three talents:\n• Coup de Grace 1/3\n• Malice 2/5\n• Efficient Strikes 2/2', summary: 'You have 5 points across three talents:', more: 0 },
  ] }));
  ring(vm);
  const lines = vm.chatLines();
  assert.ok(lines.includes('Spellmind: You have 5 points across three talents:'), JSON.stringify(lines));
  for (const l of ['   • Coup de Grace 1/3', '   • Malice 2/5', '   • Efficient Strikes 2/2']) assert.ok(lines.includes(l), l);
  const long = Array.from({ length: 7 }, (_, i) => `Line ${i + 1} of a long answer.`).join('\n');
  vm.advance(5); // the addon loads a slot at most so often
  vm.slash('tell me more');
  vm.slotText(slotFor(vm, { push: 2, acked: [`${vm.evaluate('NS.R.nonce')}_2`], records: [
    { seq: 2, t: 'reply', chat, agent: 'main', text: long, summary: 'Line 1 of a long answer.', more: 0 },
  ] }));
  ring(vm);
  const after = vm.chatLines();
  assert.ok(after.includes('Spellmind: Line 1 of a long answer. |cff888888(more: /sm)|r'), JSON.stringify(after));
  assert.ok(!after.some(l => l.includes('Line 2 of')), 'the rest only in the window');
  void key;
});

test('the app away (doorbells work, no pulse for 25 s): the strip goes, its records stay queued; the app\'s first pulse draws it again', () => {
  const vm = session();
  vm.slash('a question for later');
  assert.ok(stripRecords(vm).some(r => r.type === 'msg'), 'drawn at first (the app may be starting)');
  vm.advance(26);
  assert.equal(vm.screen(), null, 'away: nothing on screen');
  assert.equal(vm.outbox().length, 1, 'still queued');
  ring(vm, 'alive_a'); // the app starts: its first alive pulse
  assert.ok(stripRecords(vm).some(r => r.type === 'msg' && r.text === 'a question for later'), 'drawn again, the question with it');
});

test('slot-only mode (no doorbells): the app can\'t be told away, so the strip stays', () => {
  const vm = session({ signals: false });
  vm.slash('a question');
  vm.advance(30);
  assert.ok(stripRecords(vm).some(r => r.type === 'msg'));
});

test('the strip\'s spot: the top-left corner alone; 272 px down when NeverQuestAlone is loaded (its strip has the corner)', () => {
  const alone = session();
  alone.slash('hi');
  assert.equal(alone.num('NS.R.stripY'), 0);
  const beside = newVM();
  beside.run('STUB.loaded.NeverQuestAlone = true');
  beside.login().advance(3.1);
  beside.slash('hi');
  assert.equal(beside.num('NS.R.stripY'), 272);
  const r = findAndDecode(beside.screen());
  assert.equal(r.kind, 'decoded');
  assert.equal(r.geometry.y0, 272);
});

test('the review: a question the app took but never answered expires after 5 minutes with a line saying so; the fast poll stops', () => {
  const vm = session();
  vm.slash('hello?');
  const [{ key }] = vm.outbox();
  vm.run(`NS.Chat.OnAcked("${key}")`);
  assert.ok(vm.evaluate('tostring(NS.Chat.Waiting() ~= nil)') === 'true');
  vm.advance(200);
  vm.run('NS.Chat.ExpirePending()');
  assert.ok(vm.evaluate('tostring(NS.Chat.Waiting() ~= nil)') === 'true', 'not yet');
  vm.advance(120);
  vm.run('NS.Chat.ExpirePending()');
  assert.equal(vm.evaluate('tostring(NS.Chat.Waiting())'), 'nil');
  assert.match(JSON.stringify(vm.json('NS.Chat.Msgs()')), /No answer came for that question/);
});

test('/sm help lists the commands and asks the AI nothing; /sm gear opens that tab (the review)', () => {
  const vm = session();
  const before = vm.outbox().length;
  vm.slash('help');
  assert.ok(vm.chatLines().some(l => /^Spellmind commands:/.test(l)));
  assert.ok(vm.chatLines().every(l => !/\|[^|]/.test(l.replace(/\|\|/g, ''))), 'no stray | codes');
  assert.equal(vm.outbox().length, before, 'nothing sent');
  vm.slash('gear');
  assert.equal(vm.evaluate('NS.Panel.tab'), 'gear');
  assert.equal(vm.outbox().length, before);
});

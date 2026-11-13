// Milestone 3 (docs/milestone-3.md): the desktop app keeps the link's worker running.
import test from 'node:test';
import assert from 'node:assert/strict';
import { createSupervisor, NEEDS_SETUP } from '../../core/app/supervisor.mjs';

// A fake clock and fake workers: each spawn() makes one; exit(code) ends the newest.
function rig(opts = {}) {
  let t = 0;
  const timers = [];
  const kids = [];
  const states = [];
  const sup = createSupervisor({
    spawn: () => {
      const k = { exit: null, killed: false, msg: null };
      k.api = { onExit: (cb) => { k.exit = cb; }, onMessage: (cb) => { k.msg = cb; }, kill: () => { k.killed = true; if (!opts.stubborn) k.exit(null); } };
      kids.push(k);
      return k.api;
    },
    onState: s => states.push(s),
    onMessage: m => states.push({ msg: m }),
    now: () => t,
    setTimer: (fn, ms) => { const h = { at: t + ms, fn }; timers.push(h); return h; },
    clearTimer: (h) => { const i = timers.indexOf(h); if (i >= 0) timers.splice(i, 1); },
    ...opts,
  });
  const advance = (ms) => {
    t += ms;
    for (;;) {
      const due = timers.filter(h => h.at <= t).sort((a, b) => a.at - b.at)[0];
      if (!due) break;
      timers.splice(timers.indexOf(due), 1);
      due.fn();
    }
  };
  return { sup, kids, states, advance, last: () => kids[kids.length - 1] };
}

test('a worker that stops by itself starts again: 1 s, 2 s, 5 s, 15 s, then every 30 s', () => {
  const r = rig();
  r.sup.start();
  assert.equal(r.kids.length, 1);
  assert.equal(r.sup.state().phase, 'running');
  const waits = [];
  for (let i = 0; i < 6; i++) {
    r.last().exit(1);
    const s = r.sup.state();
    assert.equal(s.phase, 'restarting');
    waits.push(s.delayMs);
    r.advance(s.delayMs - 1);
    assert.equal(r.kids.length, i + 1, 'not before its wait');
    r.advance(1);
    assert.equal(r.kids.length, i + 2);
  }
  assert.deepEqual(waits, [1000, 2000, 5000, 15000, 30000, 30000]);
  assert.equal(r.sup.state().restarts, 6);
});

test('up two minutes: the next stop waits the shortest again', () => {
  const r = rig();
  r.sup.start();
  r.last().exit(1); r.advance(1000);
  r.last().exit(1); r.advance(2000);
  r.advance(120000);
  r.last().exit(1);
  assert.equal(r.sup.state().delayMs, 1000);
});

test('needs setup (exit 2): no restart until asked; a restart starts it at once', async () => {
  const r = rig();
  r.sup.start();
  r.last().exit(NEEDS_SETUP);
  assert.equal(r.sup.state().phase, 'setup');
  r.advance(60000);
  assert.equal(r.kids.length, 1, 'not restarted on its own');
  await r.sup.restart();
  assert.equal(r.kids.length, 2);
  assert.equal(r.sup.state().phase, 'running');
});

test('stop: the worker is killed and not started again; a restart from the settings starts one', async () => {
  const r = rig();
  r.sup.start();
  await r.sup.stop();
  assert.equal(r.kids[0].killed, true);
  assert.equal(r.sup.state().phase, 'stopped');
  r.advance(60000);
  assert.equal(r.kids.length, 1);
  await r.sup.restart();
  assert.equal(r.kids.length, 2);
});

test('a worker that won\'t go is let go after 5 s, so a restart isn\'t held up', async () => {
  const r = rig({ stubborn: true });
  r.sup.start();
  const p = r.sup.restart();
  r.advance(5000);
  await p;
  assert.equal(r.kids.length, 2);
  assert.equal(r.sup.state().phase, 'running');
  r.kids[0].exit(0); // the old one's late exit changes nothing
  assert.equal(r.sup.state().phase, 'running');
});

test('a worker\'s messages reach the app', () => {
  const r = rig();
  r.sup.start();
  r.last().msg({ kind: 'hello' });
  assert.deepEqual(r.states.at(-1), { msg: { kind: 'hello' } });
});

test('a spawn that throws counts as a stop: it\'s tried again', () => {
  let n = 0;
  const r = rig({ spawn: () => { n += 1; throw new Error('no'); } });
  r.sup.start();
  assert.equal(r.sup.state().phase, 'restarting');
  r.advance(1000);
  assert.equal(n, 2);
});

test('20 stops in a row: it gives up until a restart (the security review: every 30 s forever)', async () => {
  const r = rig();
  r.sup.start();
  for (let i = 0; i < 20; i++) { r.last().exit(1); r.advance(30000); }
  r.last().exit(1);
  assert.equal(r.sup.state().phase, 'gave-up');
  const n = r.kids.length;
  r.advance(600000);
  assert.equal(r.kids.length, n, 'no more tries');
  await r.sup.restart();
  assert.equal(r.sup.state().phase, 'running');
  assert.equal(r.kids.length, n + 1);
});

// The app's own updates (app/desktop/updater.mjs) against a stand-in for electron-updater: offered,
// downloaded on a click, installed only with WoW closed, only forward, errors in plain words.
import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { createUpdater, newer, errorWords, FIRST_CHECK_MS, EVERY_MS } from '../../app/desktop/updater.mjs';

function fakeUpdater({ feed = '0.5.0', failCheck = null } = {}) {
  const u = new EventEmitter();
  u.calls = [];
  u.checkForUpdates = async () => {
    u.calls.push('check');
    if (failCheck) throw failCheck;
    if (newer(feed, '0.4.0') || feed === '0.3.0') u.emit('update-available', { version: feed });
    else u.emit('update-not-available', { version: feed });
  };
  u.downloadUpdate = async () => {
    u.calls.push('download');
    u.emit('download-progress', { percent: 42.4 });
    u.emit('update-downloaded', { version: feed });
  };
  u.quitAndInstall = (silent, run) => u.calls.push(`install:${silent}:${run}`);
  return u;
}

test('a newer version: offered, downloaded on a click, then installed with WoW closed', async () => {
  const u = fakeUpdater();
  const seen = [];
  let wow = true;
  const up = createUpdater({ updater: u, current: '0.4.0', wowRunning: () => wow, onChange: (s) => seen.push(s.phase) });
  await up.check();
  assert.equal(up.state().phase, 'available');
  assert.equal(up.state().version, '0.5.0');
  assert.deepEqual(u.calls, ['check'], 'nothing downloads by itself');
  await up.download();
  assert.equal(up.state().phase, 'ready');
  assert.ok(seen.includes('downloading'));
  const blocked = up.install();
  assert.equal(blocked.ok, false);
  assert.equal(blocked.error, 'wow_running');
  assert.ok(!u.calls.some(c => c.startsWith('install')), 'never while WoW runs');
  wow = false;
  assert.equal(up.install().ok, true);
  assert.equal(u.calls.at(-1), 'install:true:true');
});

test('only forward: the same or an older version in the feed is no update', async () => {
  for (const feed of ['0.4.0', '0.3.0']) {
    const up = createUpdater({ updater: fakeUpdater({ feed }), current: '0.4.0' });
    await up.check();
    assert.equal(up.state().phase, 'none', feed);
    assert.equal((await up.download()).ok, false);
  }
  assert.equal(newer('0.4.10', '0.4.9'), true);
  assert.equal(newer('v1.0.0', '0.9.9'), true);
  assert.equal(newer('0.4.0-beta.1', '0.4.0'), false);
});

test('errors in plain words, never the raw message; a failed download keeps the offer', async () => {
  const up = createUpdater({ updater: fakeUpdater({ failCheck: Object.assign(new Error('getaddrinfo ENOTFOUND github.com'), { code: 'ENOTFOUND' }) }), current: '0.4.0' });
  await up.check();
  assert.equal(up.state().phase, 'error');
  assert.equal(up.state().error, 'No connection to GitHub right now.');
  assert.equal(errorWords(new Error('HttpError: 404 latest.yml')), 'No release to update from yet.');
  assert.doesNotMatch(errorWords(new Error('C:\\Users\\someone\\AppData x')), /Users/);

  const u = fakeUpdater();
  u.downloadUpdate = async () => { u.emit('error', new Error('sha512 checksum mismatch')); };
  const up2 = createUpdater({ updater: u, current: '0.4.0' });
  await up2.check();
  await up2.download();
  assert.equal(up2.state().phase, 'available');
  assert.match(up2.state().error, /didn't check out/);
});

test('checks: 30 s after the start, then every 6 hours; off stops them', () => {
  const t = { timeouts: [], intervals: [], cleared: 0 };
  const timers = {
    setTimeout: (fn, ms) => { t.timeouts.push(ms); return { fn }; },
    clearTimeout: () => { t.cleared++; },
    setInterval: (fn, ms) => { t.intervals.push(ms); return { fn }; },
    clearInterval: () => { t.cleared++; },
  };
  const up = createUpdater({ updater: fakeUpdater(), current: '0.4.0', timers });
  up.schedule(true);
  assert.deepEqual(t.timeouts, [FIRST_CHECK_MS]);
  assert.deepEqual(t.intervals, [EVERY_MS]);
  up.schedule(false);
  assert.equal(t.cleared, 2);
});

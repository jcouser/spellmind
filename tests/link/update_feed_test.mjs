// tools/update-feed.mjs: after signing, latest.yml says the signed installer's sha512 and size, and
// the stale .blockmap goes; anything else in the feed is left as it was.
import test from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { rewriteFeed, updateFeed } from '../../tools/update-feed.mjs';

const FEED = `version: 0.4.2
files:
  - url: Spellmind-Setup-0.4.2.exe
    sha512: OLDOLD==
    size: 100
path: Spellmind-Setup-0.4.2.exe
sha512: OLDOLD==
releaseDate: '2026-11-14T03:01:54.350Z'
`;

test('the feed gets the signed file\'s sha512 and size; the rest stays', () => {
  const out = rewriteFeed(FEED, { name: 'Spellmind-Setup-0.4.2.exe', sha512: 'NEW==', size: 123 });
  assert.equal(out, FEED.replace(/OLDOLD==/g, 'NEW==').replace('size: 100', 'size: 123'));
  assert.throws(() => rewriteFeed(FEED, { name: 'Other.exe', sha512: 'x', size: 1 }), /not Other\.exe/);
});

test('updateFeed reads the signed installer, rewrites latest.yml and removes the blockmap', (t) => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'sm-feed-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const exe = Buffer.from('signed installer bytes');
  fs.writeFileSync(path.join(dir, 'Spellmind-Setup-0.4.2.exe'), exe);
  fs.writeFileSync(path.join(dir, 'Spellmind-Setup-0.4.2.exe.blockmap'), 'stale');
  fs.writeFileSync(path.join(dir, 'latest.yml'), FEED);
  updateFeed(dir);
  const want = crypto.createHash('sha512').update(exe).digest('base64');
  const feed = fs.readFileSync(path.join(dir, 'latest.yml'), 'utf8');
  assert.equal(feed.match(new RegExp(want.replace(/[+/=]/g, '\\$&'), 'g')).length, 2);
  assert.match(feed, new RegExp(`size: ${exe.length}\\n`));
  assert.ok(!fs.existsSync(path.join(dir, 'Spellmind-Setup-0.4.2.exe.blockmap')));
});

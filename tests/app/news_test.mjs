// What's new (core/news.mjs): the order of versions, the entries since the one last seen, and the
// addon's copy of the words (Welcome.lua's WL.NEWS) the same as the app's.
import test from 'node:test';
import assert from 'node:assert/strict';
import { NEWS, newer, newsSince, digest } from '../../core/news.mjs';
import { newVM } from '../helpers/addon-vm.mjs';

test('versions: newer by each number, not by text', () => {
  assert.equal(newer('0.5.0', '0.4.7'), true);
  assert.equal(newer('0.10.0', '0.9.9'), true);
  assert.equal(newer('0.5.0', '0.5.0'), false);
  assert.equal(newer('0.4.7', '0.5.0'), false);
});

test('the news since the version last seen, up to the one running', () => {
  assert.deepEqual(newsSince('0.4.7', '0.5.0').map(n => n.version), ['0.5.0']);
  assert.deepEqual(newsSince('0.5.0', '0.5.0'), []);
  assert.deepEqual(newsSince('0.4.7', '0.4.8'), [], 'not a newer version\'s');
  assert.deepEqual(newsSince(undefined, '0.5.0').map(n => n.version), ['0.5.0']);
});

test('the addon\'s words are the app\'s, word for word', () => {
  const vm = newVM().login();
  const lua = vm.json('NS.Welcome.NEWS');
  const list = Array.isArray(lua) ? lua : Object.values(lua);
  assert.equal(list.length, NEWS.length);
  const arr = v => (Array.isArray(v) ? v : Object.values(v || {}));
  list.forEach((n, i) => {
    const want = NEWS[i];
    assert.equal(n.version, want.version);
    assert.equal(n.headline, want.headline);
    assert.equal(n.tagline, want.tagline);
    assert.equal(n.note, want.note);
    assert.deepEqual(arr(n.features).map(f => [f.title, f.text]), (want.features || []).map(f => [f.title, f.text]));
    assert.deepEqual(arr(n.changes), [...(want.changes || [])]);
  });
});

test('the digest: the newest headline; every version\'s changes newest first, each with its version when there are more', () => {
  const list = [
    { version: '0.5.0', headline: 'Meet your quest route', features: [{ title: 'A', text: 'a' }], changes: ['first'] },
    { version: '0.5.1', changes: ['a fix', 'another'] },
  ];
  const d = digest(list);
  assert.equal(d.version, '0.5.1');
  assert.equal(d.headline, 'Meet your quest route', 'skipped 0.5.0: its headline still leads');
  assert.deepEqual(d.features.map(f => f.title), ['A'], 'and its highlights');
  assert.equal(digest([list[1]]).headline, 'What\'s changed', 'a version with only changes, seen alone');
  assert.deepEqual(digest([list[1]]).features, []);
  assert.deepEqual(d.changes.map(c => c.version + ' ' + c.text), ['0.5.1 a fix', '0.5.1 another', '0.5.0 first']);
  assert.equal(d.versions, 2);
  assert.equal(digest([]), null);
});

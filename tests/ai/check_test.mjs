// Milestone 17: the double-check (core/ai/check.mjs). Fact answers are checked once more; plain chat
// isn't; the check sees the chat, the question and its draft.
import test from 'node:test';
import assert from 'node:assert/strict';
import { needsCheck, checkHistory, CHECK_ASK } from '../../core/ai/check.mjs';

test('fact questions and answers are checked; plain chat is not', () => {
  assert.equal(needsCheck('Anyone sell ammo here?', 'Yes: Vrok Blunderblast sells bullets.'), true, 'seen in game');
  assert.equal(needsCheck('How do I get to Westfall from here?', 'Head west.'), true);
  assert.equal(needsCheck('Where do I turn in Oh Brother?', 'In Stormwind.'), true);
  assert.equal(needsCheck('Is my build good?', 'Yes, it fits Combat. (source: mobalytics.gg)'), true, 'a cited answer');
  assert.equal(needsCheck('Thanks!', 'Any time.'), false);
  assert.equal(needsCheck('What should my rotation be?', 'Slice and Dice at 2+ combo points, then Sinister Strike.'), false);
  assert.equal(needsCheck('Where?', ''), false, 'nothing to check');
});

test('the check sees the chat, the question and its draft, then its own ask', () => {
  const h = checkHistory([{ role: 'user', content: 'hi' }, { role: 'assistant', content: 'hello' }], 'Anyone sell ammo?', 'Vrok does.');
  assert.deepEqual(h.slice(-2), [{ role: 'user', content: 'Anyone sell ammo?' }, { role: 'assistant', content: 'Vrok does.' }]);
  assert.equal(h.length, 4);
  assert.match(CHECK_ASK, /`world`/);
  assert.match(CHECK_ASK, /corrected answer only/);
});

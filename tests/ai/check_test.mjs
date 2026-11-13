// Milestone 17: the double-check (core/ai/check.mjs). Fact answers are checked once more; plain chat
// isn't; the check sees the chat, the question and its draft.
import test from 'node:test';
import assert from 'node:assert/strict';
import { needsCheck, checkHistory, CHECK_ASK, pickChecked } from '../../core/ai/check.mjs';

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

test('the review: a "Next:" chip doesn\'t make plain chat a fact answer; everyday words don\'t either', () => {
  assert.equal(needsCheck('thanks', 'Any time.\n\nNext: Who sells arrows here? / Where\'s the inn?'), false);
  assert.equal(needsCheck('whats my rotation', 'Backstab is in your book; open with it.'), false);
  assert.equal(needsCheck('how do I start a macro', 'Type /macro, then New.'), false);
  assert.equal(needsCheck('who sells arrows here?', 'Yanni does.'), true);
});

test('the check\'s answer is used only when it\'s an answer: not a comment, not far shorter; it keeps the draft\'s "Next:" line', () => {
  const draft = 'Yanni Stoutheart, the General Supplies vendor beside you, sells Light Shot and Heavy Shot.\n\nNext: Which shot is better? / Where is the inn?';
  assert.equal(pickChecked(draft, 'Everything above is correct.').text, draft, 'a comment');
  assert.equal(pickChecked(draft, 'Yes.').text, draft, 'far shorter');
  assert.equal(pickChecked(draft, '').text, draft);
  const fixed = 'Yanni Stoutheart, the General Supplies vendor next to you, sells Light Shot and Heavy Shot here.';
  assert.equal(pickChecked(draft, fixed).text, `${fixed}\n\nNext: Which shot is better? / Where is the inn?`, 'the chips put back');
  assert.match(CHECK_ASK, /^\[Spellmind check\]/);
  assert.match(CHECK_ASK, /hedge a claim you can't confirm/);
});

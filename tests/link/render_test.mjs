// The reply's text for the game (core/link/render.mjs): sources merged.
import test from 'node:test';
import assert from 'node:assert/strict';

test('sources side by side become one (seen in game: the model\'s own words, then the citation\'s)', async () => {
  const { markdownToWow } = await import('../../core/link/render.mjs');
  assert.equal(markdownToWow('Later. (Sources: WoWHead Classic; WoW Forever quest references.) ([wowhead.com](https://www.wowhead.com/classic/x))'),
    'Later. (sources: WoWHead Classic; WoW Forever quest references)', 'wowhead named once');
  assert.equal(markdownToWow('A ([wowhead.com](https://wowhead.com/a)) ([warcraft.wiki.gg](https://warcraft.wiki.gg/b))'), 'A (sources: wowhead.com; warcraft.wiki.gg)');
  assert.equal(markdownToWow('One ([wowhead.com](https://wowhead.com/a)).'), 'One (source: wowhead.com).', 'a single one untouched');
});

test('a "Next:" line at the end of the last paragraph still makes chips (seen in game, the audit); a plain "Next: go…" sentence stays', async () => {
  const { splitChips } = await import('../../core/link/render.mjs');
  const r = splitChips('So I can\'t name a fifth.\n\nThe tab appears inconsistent. Next: Where do I get Red Silk Bandanas? / Which Deadmines quests do I have?');
  assert.deepEqual(r.chips, ['Where do I get Red Silk Bandanas?', 'Which Deadmines quests do I have?']);
  assert.equal(r.body, 'So I can\'t name a fifth.\n\nThe tab appears inconsistent.');
  const plain = splitChips('Turn it in to Wiley. Next: head to Lakeshire.');
  assert.deepEqual(plain.chips, []);
  assert.equal(plain.body, 'Turn it in to Wiley. Next: head to Lakeshire.');
});

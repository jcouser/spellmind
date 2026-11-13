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

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

test('other AIs\' writing (the audit): Grok\'s [[1]](url) citations, tables, thinking tags and strike marks', async () => {
  const { markdownToWow } = await import('../../core/link/render.mjs');
  assert.equal(markdownToWow('Thor sells arrows [[1]](https://www.wowhead.com/classic/npc=1).'), 'Thor sells arrows (source: wowhead.com).');
  assert.equal(markdownToWow('Here:\n\n| Quest | Level |\n|---|---|\n| Red Silk | 17 |\n\nDone.'), 'Here:\n\n• Quest · Level\n• Red Silk · 17\n\nDone.');
  assert.equal(markdownToWow('<think>Let me recall the trainers…</think>\nGo north.'), 'Go north.');
  assert.equal(markdownToWow('~~Thor~~ Kelsey sells it.'), 'Thor Kelsey sells it.');
  assert.equal(markdownToWow('a | b is no table'), 'a | b is no table');
});

test('map pins: "Pin: who | zone | x, y" lines off the text, three at most; a line that isn\'t one stays (the player, 2026-11-18)', async () => {
  const { splitPins } = await import('../../core/link/render.mjs');
  const r = splitPins('Malissa sells Thieves\' Tools in Darkshire.\n\n**Pin:** Malissa | Duskwood | 79.4, 44.3\nPin: Thane Ironbelly | Ironforge | (45.2, 51.0)\nNext: How do I get there?');
  assert.deepEqual(r.pins, [{ n: 'Malissa', z: 'Duskwood', x: 79.4, y: 44.3 }, { n: 'Thane Ironbelly', z: 'Ironforge', x: 45.2, y: 51 }]);
  assert.equal(r.body, 'Malissa sells Thieves\' Tools in Darkshire.\n\nNext: How do I get there?', 'the Next: line is left for splitChips');
  assert.deepEqual(splitPins('Pin: somewhere | Duskwood | 120, 4').pins, [], 'off the map');
  assert.equal(splitPins('Pin: the map at the inn').body, 'Pin: the map at the inn', 'not a pin: kept as text');
  assert.equal(splitPins(['a', ...Array.from({ length: 5 }, (_, i) => `Pin: P${i} | Elwynn Forest | 1${i}, 20`)].join('\n')).pins.length, 3);
});

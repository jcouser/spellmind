# Spellmind

## Testing an addon change in game

The game doesn't load the addon from this repo. It loads a copy in:

```
C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\Spellmind
```

The desktop app only replaces that copy when the TOC version goes up (`core/link/install.mjs`, `shouldUpdate`), so a fix between releases never reaches the game on its own.

After changing files in `addon/Spellmind/` that the player will try in game:

1. Copy each changed file to the same path in that folder.
2. Check each copy matches the repo's file (`cmp`).
3. Tell the player to `/reload`. A changed file loads on `/reload`. A new file loads only after WoW is restarted.

Never copy over `Inbox.lua`, `Roads.lua` or `sig/` there: the app writes those while it runs.

## Tests

`npm test` runs everything. `node --test tests/addon/route_test.mjs` runs one file.

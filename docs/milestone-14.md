# Milestone 14: Professions and Gold that say what to do next

The player's verdict on the two tabs (2026-11-12): "these just seem to be duplicative data the game already provides". Both now answer "what next?" from data Spellmind has, with no AI.

## Professions

| Piece | File | What it does |
|---|---|---|
| The next rank | `Professions.lua` (NextRank) | Classic's rules: at a cap of 75 it's Journeyman (skill 50, level 10), at 150 Expert (125, 20), at 225 Artisan (200, 35). **Train Journeyman now** in green with a "train" tag when both are met. Otherwise "Expert at skill 125 and level 20", naming only what's still short. |
| Skill-ups | `Professions.lua` (Read, SkillUps) | While a profession's window is open, each learned recipe is kept with its colour (`relativeDifficulty`: orange, yellow, green, grey) and its reagents (each slot's first, with `quantityRequired`): `SpellmindDB.crafts[char][prof]`. The tab lists up to 4 orange then yellow recipes, the ones you can make first. Each shows "make 5" from the bags, and its reagents as have/need with what's short in red. The colours are the window's last look, so after skill-ups a line says to open it again. Before a window is read, it says to open it once. |
| Your materials | `Professions.lua` (Materials) | Each bag item a learned recipe uses, with the best thing it makes now (a skill-up first, then the most): "Light Leather x20: makes 5 Light Armor Kit", and "also" with others. |

## Gold

| Piece | File | What it does |
|---|---|---|
| Income | `Gold.lua` | From the game's money changes (`PLAYER_MONEY`): this session's in, out and net, and about how much an hour after 10 minutes. Today's is kept per character (`SpellmindDB.gold[char]`, reset each day). It counts from when Spellmind is running. |
| Coming up | `Gold.lua` (Costs) | Spells due at the class trainer (from the trainer's kept list) with their cost, a profession rank ready to train (its price is at the trainer), and repairs when gear is below 60%. The known costs are set against the gold carried, red when short. |
| Bag worth | `Gold.lua` (AHWorth), `Gear.SellList` | **Safe to sell at a vendor**: the same list as the merchant card, with a total. **On the auction house**: Auctionator's last scan through its public API (`Auctionator.API.v1.GetAuctionPriceByItemID`, caller "Spellmind"), for items that aren't soulbound or grey, with the top three. Without prices it says to scan, and without Auctionator it says what it would add. |

Nothing is sold, posted, crafted or bought.

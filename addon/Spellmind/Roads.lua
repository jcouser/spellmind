-- Spellmind: the roads players walk, merged (the player, 2026-11-21: "sharing of foot traffic data ... for the
-- best pathing possible"). Made from what the Spellmind app sends of the ground its players walk (squares crossed,
-- nothing else), each crossing kept only when at least 2 players' installs walked it. Written by the release build
-- and kept up to date by the app; nil until there is any. The same 8-character squares as Ground.lua, where the
-- times-walked bits count players instead (0-7, by doubling).
SpellmindRoads = nil

-- Spellmind: adapted from NeverQuestAlone's addon/NeverQuestAlone/Inbox.lua (MIT; see NOTICE.md).
-- The app's inbox for every login and /reload (NeverQuestAlone docs/PROTOCOL.md §5, "In"). The
-- Spellmind app rewrites this file on every publish with the same table as a slot file, assigned
-- to SpellmindInbox; Link.lua reads it at PLAYER_LOGIN. This placeholder just has to exist when
-- the game launches.
SpellmindInbox = nil

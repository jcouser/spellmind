# FAQ

**Is Spellmind free?**
Yes, the addon and the app are free and open source (MIT). The AI is yours: a ChatGPT plan you already pay for, or an API key billed by its maker for what you use. Your AI's maker shows what you've used on its own site.

**Do I need the app?**
No. Every tab of the panel (Quests, Dungeons, Gear, Talents, Spells, Professions, Gold), the tooltip lines and the nudges work with the addon alone. The app is for asking your AI: the chat, "Break it down" and reading your leveling guide.

**Which AI should I pick?**
Any of them works. If you have ChatGPT Plus or Pro, signing in costs nothing extra. With an API key, the app's default model for each AI is a good start; a smaller model costs less and answers faster. Turn on web search where your AI has it, so it can check quest and NPC details.

**Is it allowed?**
Spellmind is unofficial. It's built to stay inside what the game allows: the addon uses only the game's addon interface, and the app only reads Spellmind's own strip from the game's window and writes files into Spellmind's own addon folders. It never reads the game's memory, never sends input to the game and never plays for you; everything is advice you act on yourself. Only Blizzard can say what it allows, though, so read [how it reads the game](screen-reading.md) and decide for yourself.

**What does it send, and to whom?**
Your question and the game data you allow, to your AI, when you ask. Never your character's name, realm or guild. To the Spellmind authors, only the ground you walk, for the shared roads, unless you turn it off. See [privacy](privacy.md).

**Why does the addon come with 200 "Spellmind Part" addons?**
They carry answers into the game: an addon can only load files that existed when the game started, so the app writes each answer into the next free part. They're tiny, load only when needed, and sit under "Spellmind Parts" in the AddOns list. Leave them all checked.

**Why does Windows warn me about the installer?**
New apps are flagged by SmartScreen until they're signed and have a download history. Check the download's SHA-256 against the release page ([install guide](install.md)), then click **More info** → **Run anyway**. Signed releases are on the way.

**I installed the addon from CurseForge. Will the app overwrite it?**
Only with a newer version. If CurseForge's copy is newer than the app's, the app leaves it and tells you to update the app.

**Does it work on a Mac, or on Linux?**
On Linux, yes, as a preview since 0.6.7: an AppImage for WoW: Forever running under Proton or Wine (Faugus, Steam, Lutris, Heroic, Bottles). [The install guide](install.md#the-app-on-linux-preview) has the steps. Not on a Mac yet. The addon works anywhere, without the chat.

**Does it work on Classic Era, Season of Discovery or retail?**
It's made for WoW: Forever (interface 16001). Other versions aren't tested.

**The app says "WoW is running: waiting for the addon", or the chat never answers.**
The app can't hear the addon yet. In order:
1. Restart WoW once after installing: the "Spellmind Part" addons only load when the game starts.
2. In the AddOns list (character select, AddOns), tick Spellmind and every "Spellmind Part" addon.
3. Keep the top-left corner of the game's screen clear: the addon signals the app there, and another addon's frame over it blocks that.
4. Look at the app's window under Status: "Waiting for WoW" means it doesn't see the game at all; "waiting for the addon" means it sees the game but not the addon's signal; "Connected to WoW" means it all works.

Still stuck? Open an issue on [GitHub](https://github.com/jcouser/spellmind/issues) with what the Status says, and the log (below) if you can.

**The chat says "Start the Spellmind app to get answers."**
The app isn't running, or WoW was started before the addon's parts were installed. Start the app (Start menu, or its icon by the clock); if it says the addon was just installed, restart WoW once. In game, `/sm app` shows where to get it.

**Where are the logs?**
`%APPDATA%\Spellmind\logs`, or **Open the log folder** in the app. They hold no questions, answers or keys.

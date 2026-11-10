# Spellmind: AI Companion

An AI companion for World of Warcraft®: Forever. It lives in a chat window in the game, knows your character as you play (class, spec, gear, talents, bags, professions, quests) and helps with whatever you're deciding: gear to keep, equip or sell, quest rewards, talents, professions, gold and dungeons.

It runs on the AI you pick: Claude, ChatGPT, Grok or Gemini with your own API key, your ChatGPT plan by signing in, another OpenAI-compatible service, or a model on your own computer.

**It never plays for you.** It only advises, in its own window.

> **Status:** early development. Nothing to install yet. See [the design notes](docs/design.md).

> **Unofficial.** Spellmind isn't made, reviewed or endorsed by Blizzard.

## How it's built

An addon can't reach the internet, so Spellmind comes in two parts: the **addon** in the game and a small **desktop app** that talks to your AI and brings replies back. [The design notes](docs/design.md) explain how they talk to each other.

## Commands

`/spellmind` or `/sm` opens Spellmind's window.

## License

MIT, see [LICENSE](LICENSE). Parts come from NeverQuestAlone and wow-ai under the MIT license: see [NOTICE](NOTICE.md). The Spellmind name and artwork aren't covered by the license.

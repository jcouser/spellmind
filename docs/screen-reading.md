# How Spellmind reads the game

World of Warcraft addons can't use the internet, and can only save files when you log out or `/reload`. So the addon and the desktop app talk the only ways the game allows: the addon **shows** its message on screen, and the app **leaves** its answer in files the addon can load.

## From the game to the app: the strip

- When there's something to send (your question, or your character's data after it changes), the addon draws a small strip of colored squares at the top-left of the game's window. Each square's color carries a few bits of the message, with a checksum.
- The app's helper (`spellmind-capture.exe`) looks at **the game's window only**, through Windows' own screen-capture interface (DXGI Desktop Duplication). It reads the corner where the strip is drawn, decodes it, and throws the picture away.
- **Nothing else is read.** Pictures are never saved, sent or kept. The helper has no network code (its build refuses any networking library), and it captures only while the game's window is open.
- The strip is drawn only while there's something new to send; it's gone a few seconds after the app confirms it.

## From the app to the game: the parts

- The answer is written into one of the addon's 200 small "parts" (`Spellmind_S001` to `Spellmind_S200`), as a Lua file in that part's own folder.
- The app tells the addon a part is ready by adding and removing tiny silent sound files in `Spellmind\sig`, which the addon checks for. Then the addon loads that part, the same way the game loads any addon on demand.
- This is why the addon needs all its parts installed, and why a new install needs WoW restarted once (the game only sees addon files that exist when it starts).

## What Spellmind never does

- It never reads or writes the game's memory, and never injects anything into the game.
- It never sends key presses, mouse clicks or any input to the game. Everything it does is advice, shown in its own windows; waypoints are set only when you click for one.
- It never changes the game's files other than its own addon folders.
- It never reads other windows, other programs or your desktop.

## Checking it yourself

All of it is open source: the addon (`addon/Spellmind`, see `Link.lua` for the strip), the app's link (`core/link`) and the helper (`core/capture/windows`). The app's Activity list says each time it starts watching the game's window and why.

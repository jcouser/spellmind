# Spellmind's art

Made with Codex's image generation (2026-11-10), from Spellmind's own prompts. It is original art, and it is **not** covered by the MIT license (see LICENSE): a build of your own needs its own name and art.

The style is **flat and minimal**: three or four solid colours (dark indigo `#1a1040`, teal, pale white, gold), thick shapes and no texture, so every icon reads at 16–32 px. The painted first drafts turned to noise at that size.

| Source (1024 px) | In game | Used for |
|---|---|---|
| `source/logo.png`: an open book with the teal flame sigil and a gold star above it | `addon/Spellmind/Media/Spellmind.tga`, 64×64 | the addon list icon (TOC `IconTexture`, also the slot addons'), the minimap button |
| `source/portrait.png`: the arcane owl, with the sigil on its brow | `Media/Portrait.tga`, 128×128, cut to a circle | the chat window's header and the answer card |
| `source/portrait-sage.png`: the hooded sage, tried in game 2026-11-10 | (not in game) | the owl read better at 24–32 px; kept as an alternative |
| `source/mark.png`: the sigil alone | `Media/Mark.tga`, 32×32, its background made transparent, with a dark outline so it reads on parchment | the Spellmind mark on the game's windows (features.md §2.1) |

The chat window's kit (2026-11-10, after mockup A): `source/corner.png` → `Media/Corner.tga` (64×64, a top-left gold bracket, flipped in code for the other corners), `source/chevron.png` → `Media/Chevron.tga` (the thinking dropdown's arrow), `source/send.png` → `Media/Send.tga` (the send button). All are flat gold on black, with the black made transparent as for the mark, then trimmed and padded square.

The textures are uncompressed 32-bit TGA with power-of-two sides, which the game loads. Remake them from the sources with ImageMagick, from this folder:

```sh
magick source/logo.png -filter Lanczos -resize 64x64 -alpha on -compress None ../addon/Spellmind/Media/Spellmind.tga
magick source/portrait.png -resize 128x128 \( -size 128x128 xc:black -fill white -draw "circle 63.5,63.5 63.5,1.5" -blur 0x0.7 \) -alpha off -compose CopyOpacity -composite -compress None ../addon/Spellmind/Media/Portrait.tga
magick source/mark.png -resize 256x256 -fuzz 12% -fill none -draw "color 0,0 floodfill" -channel A -blur 0x0.6 +channel mark256.png
magick mark256.png -gravity center -background none -extent 280x280 \( +clone -alpha extract -morphology Dilate Disk:7 -blur 0x5 -level 0,70% \( +clone -fill "#0b0620" -colorize 100 \) +swap -alpha off -compose CopyOpacity -composite \) +swap -compose Over -composite -filter Lanczos -resize 32x32 -compress None ../addon/Spellmind/Media/Mark.tga
```

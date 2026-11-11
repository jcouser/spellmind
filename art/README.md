# Spellmind's art

Made with Codex's image generation (2026-11-10), from Spellmind's own prompts. It is original art, and it is **not** covered by the MIT license (see LICENSE): a build of your own needs its own name and art.

| Source (1024 px) | In game | Used for |
|---|---|---|
| `source/logo.png`: an open spellbook with a sigil rising | `addon/Spellmind/Media/Spellmind.tga`, 64×64 | the addon list icon (TOC `IconTexture`, also the slot addons'), the minimap button |
| `source/portrait.png`: the wisp companion, redrawn bold (big dark eyes, a dark rim, a thick crescent) so it reads at 32 px | `Media/Portrait.tga`, 128×128, cut to a circle | the chat window's header |
| `source/portrait-painted.png`: the first, painted wisp | (not in game) | detail is lost below about 64 px; kept for larger uses such as the desktop app |
| `source/mark.png`: the sigil alone, on black | `Media/Mark.tga`, 32×32, black made transparent, with a dark outline so it reads on parchment | the Spellmind mark on the game's windows (features.md §2.1) |

The textures are uncompressed 32-bit TGA with power-of-two sides, which the game loads. Remake them from the sources with ImageMagick:

```sh
magick source/logo.png -gravity center -crop 816x816+0+0 +repage -filter Lanczos -resize 64x64 -modulate 100,125 -sigmoidal-contrast 4x50% -unsharp 0x1 -alpha on -compress None ../addon/Spellmind/Media/Spellmind.tga
magick source/portrait.png -resize 128x128 \( -size 128x128 xc:black -fill white -draw "circle 63.5,63.5 63.5,1.5" -blur 0x0.7 \) -alpha off -compose CopyOpacity -composite -compress None ../addon/Spellmind/Media/Portrait.tga
magick source/mark.png -resize 256x256 \( +clone -separate -evaluate-sequence max -level 3%,60% \) \( -clone 0 -clone 1 -compose DivideSrc -composite \) -delete 0 +swap -compose CopyOpacity -composite mark256.png
magick mark256.png -gravity center -background none -extent 280x280 \( +clone -alpha extract -morphology Dilate Disk:7 -blur 0x5 -level 0,70% \( +clone -fill "#0b0620" -colorize 100 \) +swap -alpha off -compose CopyOpacity -composite \) +swap -compose Over -composite -filter Lanczos -resize 32x32 -compress None ../addon/Spellmind/Media/Mark.tga
```

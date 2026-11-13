// --shot <file.png>, from source only: a picture of the window once it's drawn, top and bottom (to
// check the layout). --shot-ai <id>: the AI picker on that AI first (its setup shown; nothing is
// switched). Not in the installed app (electron-builder.yml lists the files it takes; this isn't one),
// so the only executeJavaScript in Spellmind stays out of it (the security review).
import fs from 'node:fs';

export function shoot(win, argv) {
  const at = argv.indexOf('--shot');
  const file = at > 0 ? argv[at + 1] : null;
  if (!file) return;
  setTimeout(async () => {
    try {
      const ai = argv[argv.indexOf('--shot-ai') + 1];
      if (argv.includes('--shot-ai') && /^[a-z]+$/.test(ai || '')) {
        await win.webContents.executeJavaScript(`(() => { const s = document.getElementById('aiPick'); s.value = '${ai}'; viewing = '${ai}'; draw(last); })()`);
        await new Promise(r => setTimeout(r, 300));
      }
      fs.writeFileSync(file, (await win.webContents.capturePage()).toPNG());
      await win.webContents.executeJavaScript('window.scrollTo(0, document.body.scrollHeight)');
      await new Promise(r => setTimeout(r, 300));
      fs.writeFileSync(file.replace(/\.png$/, '-end.png'), (await win.webContents.capturePage()).toPNG());
    } catch { /* a check only */ }
  }, 2500);
}

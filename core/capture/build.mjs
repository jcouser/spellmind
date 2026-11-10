// Spellmind: adapted from NeverQuestAlone's bridge/capture/build.mjs (MIT; see NOTICE.md).
#!/usr/bin/env node
// npm run capture:build: builds this computer's screen-reading helper, where a run from source looks for it
// (bridge/transport/capture.mjs). Arguments after `--` go to the build script.
//
//   macOS    not yet in Spellmind (NeverQuestAlone's mac/build-app.sh is the model)
//            certificate (docs/get-started.md, "Screen reading from source")
//   Windows  windows/build.sh --native, with MinGW-w64's gcc on PATH, in Git Bash (its MSYSTEM tells): from
//            PowerShell or cmd, `bash` can be WSL's, which can't build it
//   Linux    nothing to build: the app reads the screen with bridge/capture_x11.py
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));

/** What builds the helper here: { cmd, args }, or { say, code } when nothing runs. */
export function buildPlan(platform = process.platform, env = process.env, extra = []) {
  // Spellmind: the macOS helper isn't brought over yet (NeverQuestAlone's is bridge/capture/mac).
  if (platform === 'darwin') return { say: 'Spellmind has no macOS capture helper yet: Windows first.', code: 1 };
  if (platform === 'win32') {
    if (!env.MSYSTEM) return { say: 'Build the Windows helper in Git Bash, with MinGW-w64\'s gcc on PATH: open Git Bash in this folder and run npm run capture:build again.', code: 1 };
    return { cmd: 'bash', args: [path.join(HERE, 'windows', 'build.sh').split(path.sep).join('/'), '--native', ...extra] };
  }
  return { say: 'Nothing to build here: on Linux the app reads the screen with bridge/capture_x11.py (python3).', code: 0 };
}

// Run as a command, by any path to it (a symlinked folder too).
const runAsCommand = () => { try { return !!process.argv[1] && fs.realpathSync(process.argv[1]) === fs.realpathSync(fileURLToPath(import.meta.url)); } catch { return false; } };
if (runAsCommand()) {
  const plan = buildPlan(process.platform, process.env, process.argv.slice(2));
  if (plan.say) {
    (plan.code ? console.error : console.log)(plan.say);
    process.exitCode = plan.code;
  } else {
    const r = spawnSync(plan.cmd, plan.args, { stdio: 'inherit' });
    if (r.error) console.error(`capture:build: ${plan.cmd} didn't start (${r.error.code ?? r.error.message})`);
    process.exitCode = r.status ?? 1;
  }
}

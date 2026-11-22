// The Linux capture helper (core/capture_x11.py): its Python tests (tests/link/capture_x11_test.py), when
// python3 is here. The test workflow's Linux job runs them, with the Codec.lua round trip (codec_test.cjs).
import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync, spawnSync } from 'node:child_process';

const HERE = path.dirname(fileURLToPath(import.meta.url));
let python = null;
try { execFileSync('python3', ['--version'], { stdio: 'ignore' }); python = 'python3'; } catch { /* none */ }

test('the Linux capture helper: Spellmind\'s magic, the strip at the corner and 272 px down, Wow.exe', { skip: python ? false : 'needs python3' }, () => {
  const r = spawnSync(python, [path.join(HERE, 'capture_x11_test.py')], { encoding: 'utf8' });
  assert.equal(r.status, 0, r.stderr + r.stdout);
  assert.match(r.stderr, /OK/);
});

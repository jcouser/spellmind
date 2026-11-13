// After a build (npm run dist): the installer's SHA-256, beside it as <installer>.sha256 and on the
// console, to publish with the download (docs/install.md; the security review: an unsigned installer
// with no hash looks the same as a tampered one).
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const { version } = JSON.parse(fs.readFileSync(path.join(HERE, '..', 'package.json'), 'utf8'));
const name = `Spellmind-Setup-${version}.exe`;
const file = path.join(HERE, '..', 'dist', name);
if (!fs.existsSync(file)) { console.error(`No ${name} in dist: build it first.`); process.exit(1); }
const sum = crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex').toUpperCase();
fs.writeFileSync(`${file}.sha256`, `${sum}  ${name}\n`);
console.log(`${name}\nSHA-256 ${sum}`);

#!/usr/bin/env node
// After the installer is signed (docs/releasing.md): the app's update feed made true again. Signing
// changes the installer's bytes, so latest.yml's sha512 and size are written again from the signed
// file, and the .blockmap (made from the unsigned bytes) is removed: without one, the app's updater
// downloads the whole installer, then checks it against latest.yml's sha512.
//
//   node tools/update-feed.mjs <dist folder>
//
// Only the sha512 and size lines change; latest.yml's other lines stay as electron-builder wrote them.
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

/** latest.yml's text with every sha512 and size for `name` set to the file's. */
export function rewriteFeed(text, { name, sha512, size }) {
  const lines = String(text).split(/\r?\n/);
  const path = /^path:\s*(.+?)\s*$/m.exec(text)?.[1];
  if (path !== name) throw new Error(`latest.yml names ${path ?? 'no file'}, not ${name}`);
  let inEntry = false, changed = 0;
  const out = lines.map((line) => {
    if (/^\s*-\s+url:\s*/.test(line)) inEntry = line.replace(/^\s*-\s+url:\s*/, '').trim() === name;
    else if (!/^\s/.test(line)) inEntry = false;
    if (/^\s*blockMapSize:/.test(line) && inEntry) { changed++; return null; }
    if (/^\s+sha512:/.test(line) && inEntry) { changed++; return line.replace(/sha512:.*/, `sha512: ${sha512}`); }
    if (/^\s+size:/.test(line) && inEntry) { changed++; return line.replace(/size:.*/, `size: ${size}`); }
    if (/^sha512:/.test(line)) { changed++; return `sha512: ${sha512}`; }
    return line;
  }).filter((l) => l !== null);
  if (changed < 3) throw new Error('latest.yml has no sha512 and size to rewrite for that file');
  return out.join('\n');
}

export function updateFeed(dist) {
  const feed = path.join(dist, 'latest.yml');
  const text = fs.readFileSync(feed, 'utf8');
  const name = /^path:\s*(.+?)\s*$/m.exec(text)?.[1];
  if (!name || name.includes('/') || name.includes('\\')) throw new Error('latest.yml has no plain path: line');
  const bytes = fs.readFileSync(path.join(dist, name));
  const sha512 = crypto.createHash('sha512').update(bytes).digest('base64');
  fs.writeFileSync(feed, rewriteFeed(text, { name, sha512, size: bytes.length }));
  fs.rmSync(path.join(dist, `${name}.blockmap`), { force: true });
  return { name, size: bytes.length, sha512 };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const dist = process.argv[2];
  if (!dist) { console.error('usage: node tools/update-feed.mjs <dist folder>'); process.exit(2); }
  const r = updateFeed(path.resolve(dist));
  console.log(`latest.yml: ${r.name}, ${r.size} bytes, sha512 ${r.sha512.slice(0, 16)}…`);
}

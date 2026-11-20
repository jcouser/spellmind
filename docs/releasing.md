# Releasing Spellmind

One version number for both parts: `app/desktop/package.json`, the addon's `## Version` in `Spellmind.toc` and `ns.VERSION` in `Core.lua`. Tests keep them equal, and the release workflow refuses a tag that doesn't match.

## A release

1. Bump the version in the three places above (and `app/desktop/package-lock.json`'s top two `"version"` lines). Run `npm test`.
   A version with something players should know about gets its What's new entry: `core/news.mjs` (the app's card after it updates) and the same words in `Welcome.lua`'s `WL.NEWS` (the game's window after the addon updates; a test keeps them equal). A big feature gets a headline, a line under it and a few highlights (each saying what it does for the player); any version can list its changes plainly (`changes`); a fix release has only those. The window (and the app's card) shows the newest release with a headline as its showcase, then a scrolling version history: every version up to this one, newest first, its changes, the ones since the player last looked marked "new". It opens after an update only when one of the new versions has a headline; a fix alone stays quiet and is in the history for `/sm news`. A version without an entry shows nothing. The first-time welcome shows the highlights of every entry after `WL.FRESH_SINCE` (Welcome.lua: the last version players had), so features added over several versions before a public release all show there; when a release is published, set it to the version before the next one.
2. Commit, then tag and push:

   ```
   git tag v0.4.1
   git push origin main v0.4.1
   ```

3. [The release workflow](../.github/workflows/release.yml) builds, from that tag:
   - the screen-reading helper, with the pinned Zig, twice (it refuses to go on unless both builds are the same bytes);
   - the tests, the installer and the addon zip;
   - a **draft** release with `Spellmind-Setup-<v>.exe`, its `.blockmap`, `latest.yml` (the app's update feed), `Spellmind-<v>.zip` and `SHA256SUMS.txt`.
4. Read the draft on GitHub. Add what changed to its notes. Publish it.
   - Installed apps see it within 6 hours (or at once with **Check now**), and offer it.
   - Don't edit or replace a published release's files: installed apps check the installer against `latest.yml`.
5. Upload the same `Spellmind-<v>.zip` to CurseForge ([curseforge.md](curseforge.md)).

A draft release is invisible to the app's updater and to "latest" links, so nothing reaches players until step 4.

## Code signing: SignPath Foundation (free for open source)

The installer is unsigned until this is set up, so Windows SmartScreen warns on first run. Everything on the repository's side is ready: the README's [code signing policy](../README.md#code-signing-policy), the SignPath steps in [the release workflow](../.github/workflows/release.yml) (off until the variables below exist), the artifact configuration in [`.signpath/artifact-configuration.xml`](../.signpath/artifact-configuration.xml), and `tools/update-feed.mjs`.

What SignPath Foundation asks (signpath.org/terms, read 2026-11-13): an OSI license with no proprietary parts (MIT, yes), a project that's maintained and already released in the form to be signed (yes, on GitHub), its function described on the download page (the README), a privacy statement ([privacy.md](privacy.md)), an uninstaller (yes), multi-factor sign-in for every team member on GitHub and SignPath, builds on GitHub's own runners (yes), and a person approving every signing request.

**1. Before applying**

- Turn on two-factor authentication on GitHub (Settings → Password and authentication), if it isn't on.

**2. Applying:** [signpath.org/apply](https://signpath.org/apply), as the maintainer. Give the repository's address, say releases are built by `release.yml` on GitHub-hosted runners from tagged commits, and point to the README's code signing policy. They decide in their own time and can say no without a reason.

**3. Once approved, in SignPath:**

- Turn on multi-factor sign-in for your SignPath account.
- Add the predefined **GitHub.com** trusted build system and link it to the project.
- Create the artifact configuration with the slug `installer` from `.signpath/artifact-configuration.xml`, and check it with **Upload an artifact sample** (an installer from a release, zipped).
- Use (or create) the signing policy with the slug `release-signing`, with yourself as approver.
- Create an API token for a user who can submit signing requests.

**4. In GitHub** (repository Settings → Secrets and variables → Actions):

- Variables `SIGNPATH_ORGANIZATION_ID` and `SIGNPATH_PROJECT_SLUG`.
- Secret `SIGNPATH_API_TOKEN`.

**5. The first signed release** (bump the minor version, e.g. 0.5.0):

- In the same release, add `publisherName: ["SignPath Foundation"]` under `win:` in `app/desktop/electron-builder.yml`. Installed apps check every later update's installer against the publisher their own copy names, so:
  - apps on 0.4.x take 0.5.0 without a check (they name none);
  - from 0.5.0 on, an update installs only if it's signed by SignPath Foundation.

  Don't add it earlier: an app naming a publisher refuses unsigned updates.
- Tag and push as usual. The build stops at "Signed through SignPath Foundation" until you approve the request in SignPath (it waits up to an hour), then puts the signed installer in place, checks its signature, rewrites `latest.yml` for the signed bytes (dropping the `.blockmap`, so updates download the whole installer) and makes the checksums from it.
- Change the README's code signing policy from "being set up" to "signed", keeping the credit line.

The certificate names SignPath Foundation as the publisher, not Spellmind.

**Status (2026-11-14):** applied; SignPath Foundation declined until the project has more community traction. Apply again once there's some to show: CurseForge downloads, GitHub stars, issues from players, threads about it. Until then releases are unsigned, and the signing steps in the release workflow stay off.

**The paid fallback:** Certum's open-source code signing certificate. It's yearly, not one-off (roughly €30-70 a year, depending on the option; check their shop), and Certum verifies the maintainer personally, so the signature shows the maintainer's own name as the publisher. It would change `publisherName` the same way. Only worth it if the SmartScreen warning visibly costs installs.

## Building by hand

```
npm ci && npm test
node tools/package-addon.mjs --out app/desktop/dist
cd app/desktop && npm ci && npm run dist
```

The helper has to be built first (`npm run capture:build` in Git Bash with MinGW-w64, or `bash core/capture/windows/build.sh` with Zig 0.16.0), or the installer has no screen reading. A local build never publishes (`--publish never`).

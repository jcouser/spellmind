# Releasing Spellmind

One version number for both parts: `app/desktop/package.json`, the addon's `## Version` in `Spellmind.toc` and `ns.VERSION` in `Core.lua`. Tests keep them equal, and the release workflow refuses a tag that doesn't match.

## A release

1. Bump the version in the three places above (and `app/desktop/package-lock.json`'s top two `"version"` lines). Run `npm test`.
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

The installer is unsigned until this is set up, so Windows SmartScreen warns on first run.

**Applying** (needs the public repository, which exists, and an OSI license, which MIT is):

1. On [signpath.org](https://signpath.org/), apply for the Open Source program with this repository. They want: the project's purpose, that releases are built by GitHub Actions from the public source, and maintainers with multi-factor authentication on GitHub.
2. Turn on two-factor authentication for every maintainer's GitHub account, if it isn't already.
3. Add the credit SignPath asks for to the README and the release notes: *Free code signing provided by [SignPath.io](https://signpath.io), certificate by [SignPath Foundation](https://signpath.org)*.

**Once approved**, SignPath gives an organization id, a project slug and a signing policy, and an API token to store as the repository secret `SIGNPATH_API_TOKEN`. Then the release workflow changes like this:

- The build job uploads the unsigned installer as an artifact; a new step runs `signpath/github-action-submit-signing-request` (pinned to a commit) with the organization id, project slug, signing policy (`release-signing`) and that artifact's id, and waits for the signed file.
- Because signing changes the installer's bytes, `latest.yml` (its `sha512` and `size`) and `SHA256SUMS.txt` are made again from the signed file before the draft release.
- `electron-builder.yml` gets `win.publisherName: ["SignPath Foundation"]`, so the app's updater installs only installers signed by that publisher. **Ship this in a release before the first signed one** is published, so every installed app checks from then on.

The certificate names SignPath Foundation as the publisher, not Spellmind. A certificate in the project's own name later (Certum's open-source certificate is a one-off cost of about €50-70) would change `publisherName` again, the same way.

## Building by hand

```
npm ci && npm test
node tools/package-addon.mjs --out app/desktop/dist
cd app/desktop && npm ci && npm run dist
```

The helper has to be built first (`npm run capture:build` in Git Bash with MinGW-w64, or `bash core/capture/windows/build.sh` with Zig 0.16.0), or the installer has no screen reading. A local build never publishes (`--publish never`).

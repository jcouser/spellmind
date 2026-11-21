# Spellmind roads

The roads players walk, shared. The Spellmind app sends what the addon recorded of the ground its player walked,
and gets back the roads merged from everyone's. The addon's route follows them along with the player's own trails.

## What's sent, and what isn't

- **Sent:** squares of the world crossed (8 yards each), for each the directions crossed out of it and whether it
  was swum, under a random id the app made for itself (not tied to the account or the character), the game and
  addon versions. The Worker keeps the day it came in.
- **Never sent:** times beyond the day, the order of travel, the character's name, realm or guild, the account, chat.
- **Shared back:** only a crossing at least 3 installs walked, so no one player's path ever shows.
- **Off:** "Share the ground I walk" on the Route tab, and the app sends nothing of that player's.
- **Deleted:** uploads are dropped after 90 days; the app can delete its install's at any time
  (`DELETE /v1/ground/<id>`).

## How it fits together

```
addon (Ground.lua)  --SavedVariables-->  app  --POST /v1/ground-->  Worker  --R2: up/<id>/<day>-<time>.json
                                                                       |
weekly GitHub Action (tools/roads-merge.mjs) --admin routes--> merge --PUT /v1/admin/roads--> R2: roads/latest.json
                                                                       |
app  <--GET /v1/roads--  Worker            release build  <--GET /v1/roads--  Worker  --> addon/Spellmind/Roads.lua
```

The Worker only stores and serves: a free Worker gets 10 ms of CPU a request, too little to merge, and a free
D1 database too few writes. Uploads are files in R2 (free: 10 GB, a million writes a month), merged once a week by
a GitHub Action (free for a public repository).

## Setting it up (once)

1. A Cloudflare account (free). In the dashboard, R2: create a bucket named `spellmind-roads` (R2 asks for a card
   on file even on the free plan; nothing is charged within its free allowance).
2. From this folder: `npx wrangler login`, then `npx wrangler deploy`. It prints the Worker's address,
   `https://spellmind-roads.<your subdomain>.workers.dev`.
3. An admin token, any long random string: `npx wrangler secret put ADMIN_TOKEN`.
4. On GitHub, the repository's Settings, Secrets and variables, Actions: the variable `ROADS_URL` (the Worker's
   address) and the secret `ROADS_ADMIN_TOKEN` (the same token).
5. The app's `ROADS_URL` (core/roads/share.mjs) set to the Worker's address, in the release that turns sharing on.

`node tools/roads-merge.mjs` with `ROADS_URL` and `ROADS_ADMIN_TOKEN` set runs the merge by hand; the Actions tab
runs it with "roads", Run workflow.

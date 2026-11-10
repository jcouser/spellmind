# Notices

Spellmind is its own addon and app. Some of its code comes from other open-source projects, used under their licenses. Each copied file keeps a header naming where it came from, and this page lists them.

## NeverQuestAlone (MIT)

From [tommygeoco/neverquestalone](https://github.com/tommygeoco/neverquestalone), version 1.4.19 plus the ChatGPT plan sign-in (pull request #2):

- `core/ai/providers/adapters/anthropic.mjs` ← `bridge/byok/providers/adapters/anthropic.mjs`
- `core/ai/providers/adapters/openai.mjs` ← `bridge/byok/providers/adapters/openai.mjs`
- `core/ai/providers/display.mjs` ← `bridge/byok/providers/display.mjs`
- `core/ai/providers/errors.mjs` ← `bridge/byok/providers/errors.mjs`
- `core/ai/providers/index.mjs` ← `bridge/byok/providers/index.mjs`
- `core/ai/providers/keytext.mjs` ← `bridge/byok/providers/keytext.mjs`
- `core/ai/providers/manifests/anthropic.json` ← `bridge/byok/providers/manifests/anthropic.json`
- `core/ai/providers/manifests/chatgpt.json` ← `bridge/byok/providers/manifests/chatgpt.json`
- `core/ai/providers/manifests/custom.json` ← `bridge/byok/providers/manifests/custom.json`
- `core/ai/providers/manifests/google.json` ← `bridge/byok/providers/manifests/google.json`
- `core/ai/providers/manifests/openai.json` ← `bridge/byok/providers/manifests/openai.json`
- `core/ai/providers/manifests/xai.json` ← `bridge/byok/providers/manifests/xai.json`
- `core/ai/providers/setup-errors.mjs` ← `bridge/byok/providers/setup-errors.mjs`
- `core/ai/providers/sse.mjs` ← `bridge/byok/providers/sse.mjs`
- `core/ai/providers/util.mjs` ← `bridge/byok/providers/util.mjs`
- `core/ai/runqueue.mjs` ← `bridge/byok/runqueue.mjs`
- `core/ai/security/egress.mjs` ← `bridge/byok/security/egress.mjs`
- `core/ai/security/keycheck.mjs` ← `bridge/byok/security/keycheck.mjs`
- `core/ai/security/keystore.mjs` ← `bridge/byok/security/keystore.mjs`
- `core/ai/security/redact.mjs` ← `bridge/byok/security/redact.mjs`
- `core/ai/signin/chatgpt.mjs` ← `bridge/byok/signin/chatgpt.mjs`
- `core/ai/signin/index.mjs` ← `bridge/byok/signin/index.mjs`
- `core/ai/usage/caps.mjs` ← `bridge/byok/usage/caps.mjs`
- `core/ai/usage/fuse.mjs` ← `bridge/byok/usage/fuse.mjs`
- `core/ai/usage/history.mjs` ← `bridge/byok/usage/history.mjs`
- `core/ai/usage/meter.mjs` ← `bridge/byok/usage/meter.mjs`
- `core/ai/usage/prices.json` ← `bridge/byok/usage/prices.json`
- `core/ai/usage/prices.mjs` ← `bridge/byok/usage/prices.mjs`
- `core/files.mjs` ← `bridge/files.mjs`
- `core/log.mjs` ← `bridge/log.mjs`
- `tests/ai/egress_test.mjs` ← `tests/byok/egress_test.mjs`
- `tests/ai/helpers/canary.mjs` ← `tests/byok/helpers/canary.mjs`
- `tests/ai/helpers/mock-provider.mjs` ← `tests/byok/helpers/mock-provider.mjs`
- `tests/ai/keycheck_test.mjs` ← `tests/byok/keycheck_test.mjs`
- `tests/ai/keystore_test.mjs` ← `tests/byok/keystore_test.mjs`
- `tests/ai/keytext_test.mjs` ← `tests/byok/keytext_test.mjs`
- `tests/ai/providers_anthropic_test.mjs` ← `tests/byok/providers_anthropic_test.mjs`
- `tests/ai/providers_custom_test.mjs` ← `tests/byok/providers_custom_test.mjs`
- `tests/ai/providers_errors_test.mjs` ← `tests/byok/providers_errors_test.mjs`
- `tests/ai/providers_manifest_test.mjs` ← `tests/byok/providers_manifest_test.mjs`
- `tests/ai/providers_midstream_test.mjs` ← `tests/byok/providers_midstream_test.mjs`
- `tests/ai/providers_openai_test.mjs` ← `tests/byok/providers_openai_test.mjs`
- `tests/ai/providers_sse_test.mjs` ← `tests/byok/providers_sse_test.mjs`
- `tests/ai/providers_stream_test.mjs` ← `tests/byok/providers_stream_test.mjs`
- `tests/ai/redact_test.mjs` ← `tests/byok/redact_test.mjs`
- `tests/ai/setup_errors_test.mjs` ← `tests/byok/setup_errors_test.mjs`
- `tests/ai/signin_chatgpt_test.mjs` ← `tests/byok/signin_chatgpt_test.mjs`
- `tests/ai/usage_caps_test.mjs` ← `tests/byok/usage_caps_test.mjs`
- `tests/ai/usage_fuse_test.mjs` ← `tests/byok/usage_fuse_test.mjs`
- `tests/ai/usage_history_test.mjs` ← `tests/byok/usage_history_test.mjs`
- `tests/ai/usage_meter_test.mjs` ← `tests/byok/usage_meter_test.mjs`
- `tests/ai/usage_prices_test.mjs` ← `tests/byok/usage_prices_test.mjs`
- `tests/helpers/luavm.mjs` ← `tests/helpers/luavm.mjs`
- `tests/fixtures/ai/providers/` ← `tests/fixtures/byok/providers/` (the providers' recorded answers)

NeverQuestAlone is itself built on [chelinho139/wow-ai](https://github.com/chelinho139/wow-ai) (MIT), which worked out how an addon talks to a program outside the game: a strip of colored pixels the addon draws (an idea wow-ai credits to wow-forever-codex), and addon files the program writes for the game to load.

Their notice, as the MIT license requires:

```
MIT License

Copyright (c) 2026 chelinho139
Copyright (c) 2026 The NeverQuestAlone authors (NeverQuestAlone fork changes)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

NeverQuestAlone's name and artwork aren't part of its license, and Spellmind uses neither.

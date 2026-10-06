# Gemini CLI and Antigravity

Agent Usage collects Google usage on the Mac and shares the resulting snapshots
through Continuity Sync. Enable either provider in Settings → Providers and grant
local data access through Settings → Local Data Access.

## Gemini CLI

Sign in to Gemini CLI with your Google account. Agent Usage reads its OAuth session
from `~/.gemini/oauth_creds.json` and fetches the account's model quotas. API-key
and Vertex logins still support local token tracking, but their live quotas use a
different accounting system and are not included here. Enterprise users can supply
`GOOGLE_CLOUD_PROJECT` or `GOOGLE_CLOUD_PROJECT_ID` to the Agent Usage process.

Local token totals come from `~/.gemini/tmp/<project>/chats/`. Both legacy JSON
and current JSONL recordings are supported, including message updates and rewinds.
The current JSONL copy takes precedence over a migrated JSON copy. Cached prompt
tokens are separated from fresh input; thinking tokens count toward output cost.
Costs are estimated text API equivalents using LiteLLM pricing, with published
Google fallback rates, covering the 2.5 family, 3/3.1 Pro previews, 3 Flash
preview, 3.5–3.8 Flash, and 3.1/3.5 Flash-Lite. Historical 2.0 model IDs and
provider-prefixed names are accepted. Promotional pricing follows each usage
record’s date, and long-context Pro prompts use the higher tier. Unknown future
model IDs remain discoverable and can use the live pricing cache. These estimates do not represent the subscription bill, credit use,
multimodal charges, grounding charges, or cache storage fees.

Gemini 4 Argon was announced on September 30, 2026 with limited initial access.
Google announced introductory prices of $2 per million input tokens and $10 per
million output tokens, with cached input discounted by 95%; subsequent prices
will be $4/$20. As of October 6, its public API catalog does not list a model ID
or an introductory-period end date. Quota discovery and log parsing accept new
model IDs dynamically, but there is no hardcoded Argon pricing fallback until
the billable ID and applicable pricing period can be verified.

## Antigravity

Sign in through Antigravity on the Mac. Agent Usage reads the IDE's existing
Google access token from `state.vscdb` in the `User/globalStorage` directory under
`~/Library/Application Support/Antigravity`, `Antigravity IDE`, or `antigravity`.
It supports both unified OAuth state and older agent-manager/auth-status entries.
The database is opened read-only, including its active WAL state. Antigravity owns
its token renewal; reopen or sign in through Antigravity if the token expires.

Model quotas, including proxied Claude models, remain attributed to Antigravity.
The provider currently supplies quota windows only. Antigravity CLI token logs and
an independent Agent Usage Google login are outside this implementation.

## Quota compatibility

Google's internal Code Assist quota endpoints can change or deny access for an
account. Missing percentages or reset timestamps are omitted. Model-catalog
allowances that all appear full are verified against actual quota buckets before
publication. Failures keep the last snapshot with a provider-specific error;
HTTP 429 respects the app's refresh cooldown, and HTTP 5xx participates in outage
tracking. Window durations remain unknown because the responses supply reset
instants rather than period lengths.

Credentials stay on the Mac. Each tool owns its token renewal; run Gemini CLI or
reopen Antigravity when its session expires, then refresh usage. Agent Usage
reloads access tokens on each refresh, without reading refresh tokens, embedding
OAuth client credentials, or rewriting either tool's credential store. iOS and widgets consume published
usage through the existing CloudKit path, without provider authentication.

## Integration references

- [Gemini session storage](https://github.com/google-gemini/gemini-cli/blob/main/docs/cli/session-management.md)
- [Gemini recording schema](https://github.com/google-gemini/gemini-cli/blob/main/packages/core/src/services/chatRecordingService.ts)
- [Code Assist quota requests](https://github.com/google-gemini/gemini-cli/blob/main/packages/core/src/code_assist/server.ts)
- [Gemini CLI model definitions](https://github.com/google-gemini/gemini-cli/blob/main/packages/core/src/config/models.ts)
- [Legacy pricing snapshot](https://github.com/BerriAI/litellm/blob/13e74dd389ef131631ef045620b2c253b1178b8c/model_prices_and_context_window.json)
- [Google text API pricing](https://ai.google.dev/gemini-api/docs/pricing)
- [Gemini 4 Argon announcement](https://blog.google/innovation-and-ai/models-and-research/gemini-models/gemini-4-argon/)
- [Antigravity quota integration reference](https://github.com/steipete/CodexBar/blob/main/Sources/CodexBarCore/Providers/Antigravity/AntigravityRemoteUsageFetcher.swift)
- [Antigravity unified state layout](https://github.com/lbjlaq/Antigravity-Manager/blob/main/src-tauri/src/utils/protobuf.rs)

Monochrome provider marks are sourced from [Simple Icons](https://github.com/simple-icons/simple-icons)
(Gemini, CC0) and [Lobe Icons](https://github.com/lobehub/lobe-icons) (Antigravity, MIT).

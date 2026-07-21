# Grammar Alfred

An [Alfred 5](https://www.alfredapp.com/) workflow that fixes your English grammar and orthography using an LLM — without changing meaning, tone, or language. Built for non-native speakers who write to native speakers all day and want the Gemini-tab round-trip gone.

Copy text → hotkey → corrected version in your clipboard, with a short change list and an explanation in your own language so you learn the patterns.

## Triggers

| Trigger | How |
|---|---|
| **Hotkey** `⌃⌘G` (Control+Command+G) | Copy any text (`⌘C`), press the hotkey — your clipboard becomes the input. Re-record in Alfred if you prefer another combo. |
| **Keyword** `grammar <text>` | Type inline to compose-and-check without leaving Alfred. |

Both share the same provider and model configuration.

## Result

- **`✏ corrected text`** — press `↵` to copy, then `⌘V` back into Slack/email/docs. Subtitle shows what changed.
  - `⌘↵` copies the explanation instead.
- **`💡 explanation`** — press `⇧` (Shift) to open the full note (original, corrected, change list, rationale) in Quick Look.

## Setup

1. Install [`jq`](https://stedolan.github.io/jq/) and `curl`: `brew install jq curl`
2. Double-click `grammar.alfredworkflow` to install in Alfred.
3. Open the workflow → **Configure Workflow…** and fill in:

| Variable | Example | Notes |
|---|---|---|
| `Provider` | `OpenAI` *(dropdown)* | Pick from the list. Select “Custom URL” to use your own endpoint. |
| `Custom Endpoint` | `https://my-proxy.com/v1/chat/completions` | Only used when Provider = “Custom URL”. Format auto-detected from the path. |
| `API Key` | `sk-…` / `sk-ant-…` / `AIza…` | Required for cloud providers. Not needed for `ollama` or a local custom URL. |
| `Model` | `gemini-2.5-flash` | Leave blank for the provider's default (a cheap/fast current tier). |
| `Explanation Language` | `Spanish` | Language of the explanation note. |

> `prefs.plist` holds your personal values (including the API key) and is git-ignored. `API_KEY` is also in `variablesdontexport` so Alfred never exports it.

### Provider dropdown

`OpenAI` · `Anthropic Claude` · `Google Gemini` · `xAI Grok` · `DeepSeek` · `Alibaba Qwen` · `Moonshot Kimi` · `Xiaomi MiMo` · `MiniMax` · `Z.ai GLM` · `OpenRouter` · `OpenCode Go` · `Ollama (local)` · `Custom URL`

Defaults are the cheapest viable 2026-current tier per provider (verified via [models.dev](https://models.dev) + official docs). Override with `Model`.

| `PROVIDER` | Format | Default `MODEL` | Endpoint |
|---|---|---|---|
| `openai` | openai | `gpt-4.1-mini` | `api.openai.com/v1/chat/completions` |
| `anthropic` | anthropic | `claude-haiku-4-5` | `api.anthropic.com/v1/messages` |
| `gemini` | gemini | `gemini-2.5-flash` | `…googleapis.com` (`:generateContent`) |
| `grok` | openai | `grok-4.3` | `api.x.ai/v1/chat/completions` |
| `deepseek` | openai | `deepseek-v4-flash` | `api.deepseek.com/chat/completions` |
| `qwen` | openai | `qwen3.6-flash` | `dashscope.aliyuncs.com/compatible-mode/v1/…` |
| `kimi` | openai | `kimi-k3` | `api.moonshot.ai/v1/chat/completions` |
| `mimo` | openai | `mimo-v2.5` | `api.xiaomimimo.com/v1/chat/completions` |
| `minimax` | openai | `MiniMax-M3` | `api.minimax.io/v1/chat/completions` |
| `zai` | openai | `glm-4.6` | `api.z.ai/api/paas/v4/chat/completions` |
| `openrouter` | openai | *(set `MODEL`)* | `openrouter.ai/api/v1/chat/completions` |
| `opencode-go` | openai | `kimi-k3` | `opencode.ai/zen/go/v1/chat/completions` |
| `ollama` | openai | `llama3.2` | `localhost:11434` (no key) |

**Custom endpoint:** choose “Custom URL” in the Provider dropdown and paste a full URL into `Custom Endpoint`. Format is auto-detected from the path (`/messages` → anthropic, `:generateContent` / `googleapis.com` → gemini, else openai). `localhost`/`127.0.0.1` skips the API-key check.

**Cheapest tier notes:** for Gemini, `gemini-2.5-flash-lite` ($0.10/$0.40) is the floor; `gemini-2.5-flash` ($0.30/$2.50) is the default for better grammar nuance. `gemini-2.0-flash` is **shut down**. Z.ai's `glm-4.5-flash` is free.

## Build

```bash
./package.sh
```

Produces `grammar.alfredworkflow`. The script lints `check.sh`, validates `info.plist`, bundles the files, and runs a no-key smoke test.

## Structure

```
grammar-alfred/
├── info.plist          # workflow: keyword + hotkey → Script Filter → Copy to Clipboard
├── scripts/check.sh    # multi-provider LLM call → Alfred Script Filter JSON
├── package.sh          # build + smoke test
├── icon.png            # optional; drop one in to brand the workflow
├── README.md
└── LICENSE
```

## Privacy

Text you check is sent to the LLM provider you configure. For fully private/offline checking, point `ENDPOINT` at a local Ollama server.

## License

MIT © EstebanForge

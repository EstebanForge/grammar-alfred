#!/usr/bin/env bash
#
# Grammar Alfred — multi-provider LLM grammar & orthography checker.
# Reads text from {query} (or clipboard fallback), asks the configured LLM to
# return a corrected version (meaning preserved) plus a short change list and a
# brief explanation, then emits Alfred Script Filter JSON.
#
# PROVIDER is a dropdown alias (openai, anthropic, gemini, grok, deepseek, qwen,
# kimi, mimo, minimax, zai, openrouter, opencode-go, ollama) or "custom".
# "custom" routes to CUSTOM_ENDPOINT. The resolver maps either to the exact
# endpoint + wire format (openai | anthropic | gemini) + default model.
#
# Workflow variables (set in Alfred's config UI):
#   PROVIDER         alias from the dropdown, or "custom"
#   CUSTOM_ENDPOINT  full URL, used only when PROVIDER = custom
#   API_KEY          provider API key (ignored for local Ollama / local URLs)
#   MODEL            model id (optional; provider default used if blank)
# Optional:
#   EXPLAIN_LANG     language for the explanation note (default: Spanish)
#
# Compatible with macOS system /bin/bash 3.2 (Alfred's runtime). No bash 4+
# features (no ${var,,}, no ${var^^}, no associative arrays, no mapfile).

set -euo pipefail

# ── debug log setup ──────────────────────────────────────────────────────────
# Defined FIRST so curl stderr capture in provider calls works. Files live in
# Alfred's standard workflow data dir.
log_dir="${alfred_workflow_data:-$HOME/Library/Caches/com.runningwithcrayons.Alfred/Workflow Data/com.estebanforge.alfred.grammar}"
mkdir -p "$log_dir" 2>/dev/null || true
log_file="$log_dir/debug.log"
resp_file="$log_dir/last-response.json"
stderr_file="$log_dir/curl-stderr.log"
: > "$stderr_file" 2>/dev/null || true   # truncate per-run

# ── helpers ──────────────────────────────────────────────────────────────────

emit_error() {
    local title="$1" subtitle="${2:-}" quicklook="${3:-}"
    if [[ -n "$quicklook" ]]; then
        jq -n --arg t "$title" --arg s "$subtitle" --arg q "$quicklook" \
            '{items:[{title:$t, subtitle:$s, valid:false, quicklookurl:$q}]}'
    else
        jq -n --arg t "$title" --arg s "$subtitle" \
            '{items:[{title:$t, subtitle:$s, valid:false}]}'
    fi
    exit 0
}

# ── dependencies ─────────────────────────────────────────────────────────────

for bin in jq curl; do
    if ! command -v "$bin" >/dev/null 2>&1; then
        emit_error "⚠ $bin not found" "Install with: brew install $bin"
    fi
done

# ── input ────────────────────────────────────────────────────────────────────

# Alfred passes the query as $1. Hotkey-trigger objects and the keyword both
# feed {query}. Fall back to the macOS clipboard if invoked empty.
query="${1:-}"
query="${query#grammar}"   # tolerate a leading "grammar" token from manual runs
query="$(printf '%s' "$query" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

if [[ -z "$query" ]]; then
    query="$(pbpaste 2>/dev/null || true)"
    query="$(printf '%s' "$query" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
fi

if [[ -z "$query" ]]; then
    emit_error "✍ Nothing to check" "Copy some text, or type: grammar <your text>"
fi

# ── provider resolution ──────────────────────────────────────────────────────
#
# Resolves PROVIDER into:
#   GLM_ENDPOINT  base URL (provider functions append the path)
#   GLM_FORMAT    openai | anthropic | gemini
#   GLM_MODEL     default model (may be empty)
#   GLM_KEYLESS   1 if no API key required (local servers)
#   GLM_ENVVARS   space-separated standard env var names to try if API_KEY unset

GLM_ENDPOINT="" GLM_FORMAT="" GLM_MODEL="" GLM_KEYLESS=0 GLM_ENVVARS=""

resolve_provider() {
    local input="$1" lc
    lc="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"   # bash 3.2-safe

    # Default models verified current as of 2026-07. Cheapest viable tier per
    # provider (models.dev + official docs). Override with MODEL.
    case "$lc" in
        # ── Big three (native formats) ──
        openai|"openai")
            GLM_ENDPOINT="https://api.openai.com"
            GLM_FORMAT="openai"; GLM_MODEL="gpt-4.1-mini"; GLM_ENVVARS="OPENAI_API_KEY" ;;
        anthropic|claude|"anthropic claude")
            GLM_ENDPOINT="https://api.anthropic.com"
            GLM_FORMAT="anthropic"; GLM_MODEL="claude-haiku-4-5"; GLM_ENVVARS="ANTHROPIC_API_KEY" ;;
        gemini|google|"google gemini")
            GLM_ENDPOINT="https://generativelanguage.googleapis.com"
            GLM_FORMAT="gemini"; GLM_MODEL="gemini-2.5-flash"; GLM_ENVVARS="GEMINI_API_KEY GOOGLE_API_KEY" ;;
        # ── OpenAI-compatible providers ──
        grok|xai|"xai grok")
            GLM_ENDPOINT="https://api.x.ai"
            GLM_FORMAT="openai"; GLM_MODEL="grok-4.3"; GLM_ENVVARS="XAI_API_KEY GROK_API_KEY" ;;
        deepseek)
            GLM_ENDPOINT="https://api.deepseek.com"
            GLM_FORMAT="openai"; GLM_MODEL="deepseek-v4-flash"; GLM_ENVVARS="DEEPSEEK_API_KEY" ;;
        qwen|dashscope|alibaba|"alibaba qwen")
            GLM_ENDPOINT="https://dashscope.aliyuncs.com"
            GLM_FORMAT="openai"; GLM_MODEL="qwen3.6-flash"; GLM_ENVVARS="DASHSCOPE_API_KEY" ;;
        kimi|moonshot|"moonshot kimi")
            GLM_ENDPOINT="https://api.moonshot.ai"
            GLM_FORMAT="openai"; GLM_MODEL="kimi-k3"; GLM_ENVVARS="MOONSHOT_API_KEY KIMI_API_KEY" ;;
        mimo|xiaomi|"xiaomi mimo")
            GLM_ENDPOINT="https://api.xiaomimimo.com"
            GLM_FORMAT="openai"; GLM_MODEL="mimo-v2.5"; GLM_ENVVARS="MIMO_API_KEY XIAOMI_API_KEY" ;;
        minimax)
            GLM_ENDPOINT="https://api.minimax.io"
            GLM_FORMAT="openai"; GLM_MODEL="MiniMax-M3"; GLM_ENVVARS="MINIMAX_API_KEY" ;;
        zai|glm|z.ai|zhipu|"z.ai glm")
            GLM_ENDPOINT="https://api.z.ai"
            GLM_FORMAT="openai"; GLM_MODEL="glm-4.6"; GLM_ENVVARS="ZAI_API_KEY ZHIPUAI_API_KEY ZHIPU_API_KEY" ;;
        openrouter)
            GLM_ENDPOINT="https://openrouter.ai"
            GLM_FORMAT="openai"; GLM_MODEL=""; GLM_ENVVARS="OPENROUTER_API_KEY" ;;
        opencode-go|opencode|"opencode go")
            GLM_ENDPOINT="https://opencode.ai"
            GLM_FORMAT="openai"; GLM_MODEL="kimi-k3"; GLM_ENVVARS="OPENCODE_API_KEY" ;;
        ollama|local|"ollama (local)")
            GLM_ENDPOINT="http://localhost:11434"
            GLM_FORMAT="openai"; GLM_MODEL="llama3.2"; GLM_KEYLESS=1 ;;
        "")
            GLM_ENDPOINT="https://api.openai.com"
            GLM_FORMAT="openai"; GLM_MODEL="gpt-4.1-mini" ;;
        *)
            resolve_url "$input" ;;
    esac
}

resolve_url() {
    local u="$1"
    [[ "$u" != "http://"* && "$u" != "https://"* ]] && u="https://$u"
    u="${u%/}"
    [[ "$u" == *"localhost"* || "$u" == *"127.0.0.1"* ]] && GLM_KEYLESS=1
    # Format auto-detection from the URL path.
    if [[ "$u" == *"/interactions"* || "$u" == *"generativelanguage.googleapis.com"* ]]; then
        GLM_FORMAT="gemini"; GLM_ENDPOINT="$u"; GLM_MODEL="gemini-2.5-flash"
    elif [[ "$u" == *"/messages"* || "$u" == *"anthropic.com"* ]]; then
        GLM_FORMAT="anthropic"; GLM_ENDPOINT="$u"; GLM_MODEL="claude-haiku-4-5"
    else
        GLM_FORMAT="openai"; GLM_ENDPOINT="$u"; GLM_MODEL=""
    fi
}

provider_input="${PROVIDER:-openai}"
provider_input_lc="$(printf '%s' "$provider_input" | tr '[:upper:]' '[:lower:]')"
custom_endpoint="${CUSTOM_ENDPOINT:-}"
api_key="${API_KEY:-}"
model="${MODEL:-}"
explain_lang="${EXPLAIN_LANG:-Spanish}"

if [[ "$provider_input_lc" == "custom" ]]; then
    if [[ -z "$custom_endpoint" ]]; then
        emit_error "⚠ Custom endpoint empty" "Set CUSTOM_ENDPOINT in workflow config (Provider = Custom)"
    fi
    resolve_url "$custom_endpoint"
else
    resolve_provider "$provider_input"
fi
format="$GLM_FORMAT"
endpoint="$GLM_ENDPOINT"
[[ -z "$model" ]] && model="$GLM_MODEL"

if [[ "$GLM_KEYLESS" -eq 0 && -z "$api_key" ]]; then
    emit_error "⚠ No API key set" "Open the workflow config and set API_KEY for '$provider_input'"
fi
if [[ -z "$model" ]]; then
    emit_error "⚠ No model set" "This provider needs MODEL in workflow config (e.g. grok-4-fast, openrouter/qwen-2.5)"
fi

# ── prompt ───────────────────────────────────────────────────────────────────
# `read -d ''` consumes the heredoc without a $(...) wrapper — avoids a bash 3.2
# command-substitution tokenizer bug where an apostrophe in the body sends it
# hunting for a matching quote to EOF. `|| true` because read returns non-zero
# at EOF (set -e would otherwise abort).
IFS='' read -r -d '' sys_prompt <<EOF || true
You are a meticulous grammar and orthography corrector for non-native English speakers.
Fix the user's text without changing its meaning, tone, register, or language.
Preserve code blocks, URLs, handles, and Markdown formatting exactly.

Return ONLY a minified JSON object on a single line. No prose, no Markdown fences.
Schema:
{"corrected":"<corrected text>","changes":["<one short change each>"],"explanation":"<brief rationale in ${explain_lang}, one sentence per change>"}

Rules:
- If the text is already correct, return it unchanged with an empty "changes" array.
- Each entry in "changes" must be short, e.g. "their -> there" or "+ this".
- "explanation" uses ${explain_lang} only; keep it concise.
EOF

# ── provider call ────────────────────────────────────────────────────────────
# All three return the FULL raw body (no `curl -f`) so HTTP error bodies survive
# and we can surface the provider's own message. Each captures curl's network-
# level stderr to $stderr_file for diagnostics.

call_openai() {
    local body
    body=$(jq -n \
        --arg sys "$sys_prompt" \
        --arg user "$query" \
        --arg model "$model" \
        '{model:$model, temperature:0.2,
          messages:[{role:"system",content:$sys},{role:"user",content:$user}]}')
    curl -sS -m 30 \
        -H "Authorization: Bearer ${api_key}" \
        -H 'content-type: application/json' \
        -H 'accept: application/json' \
        --data-raw "$body" \
        "${endpoint%/}/v1/chat/completions" \
        2>"$stderr_file"
}

call_anthropic() {
    local body
    body=$(jq -n \
        --arg sys "$sys_prompt" \
        --arg user "$query" \
        --arg model "$model" \
        '{model:$model, max_tokens:1024, temperature:0.2, system:$sys,
          messages:[{role:"user",content:$user}]}')
    curl -sS -m 30 \
        -H "x-api-key: $api_key" \
        -H 'anthropic-version: 2023-06-01' \
        -H 'content-type: application/json' \
        --data-raw "$body" \
        "${endpoint%/}/v1/messages" \
        2>"$stderr_file"
}

call_gemini() {
    # Interactions API (GA June 2026; recommended over legacy :generateContent).
    # Single endpoint, header auth (keeps the key out of URLs/logs), simple
    # request shape: {model, system_instruction, input}. store=false = stateless,
    # matching our one-shot grammar-check use case.
    local body
    body=$(jq -n \
        --arg sys "$sys_prompt" \
        --arg user "$query" \
        --arg model "$model" \
        '{model:$model, system_instruction:$sys, input:$user,
          generation_config:{temperature:0.2}, store:false}')
    curl -sS -m 30 \
        -H "x-goog-api-key: ${api_key}" \
        -H 'content-type: application/json' \
        --data-raw "$body" \
        "${endpoint%/}/v1beta/interactions" \
        2>"$stderr_file"
}

case "$format" in
    openai)    resp_raw="$(call_openai)"    || resp_raw="" ;;
    anthropic) resp_raw="$(call_anthropic)" || resp_raw="" ;;
    gemini)    resp_raw="$(call_gemini)"    || resp_raw="" ;;
    *)
        emit_error "⚠️ Internal error" "Unknown format '$format'"
        ;;
esac

# ── debug log ────────────────────────────────────────────────────────────────
# Append a timestamped record of every run so failures can be diagnosed after
# the fact. Auto-trims to keep the file bounded.
{
    printf '===== %s =====\n' "$(date '+%Y-%m-%d %H:%M:%S')"
    printf 'provider=%s format=%s model=%s endpoint=%s\n' "$provider_input_lc" "$format" "$model" "$endpoint"
    printf 'api_key_len=%s\n' "${#api_key}"
    printf 'query=%s\n' "$query"
    printf -- '---- raw response (%d bytes) ----\n' "${#resp_raw}"
    printf '%s\n' "$resp_raw"
    if [[ -s "$stderr_file" ]]; then
        printf -- '---- curl stderr ----\n'
        cat "$stderr_file" 2>/dev/null
    fi
    printf '\n'
} >>"$log_file" 2>/dev/null || true

if [[ -f "$log_file" ]] && [[ $(wc -c < "$log_file" | tr -d ' ') -gt 200000 ]]; then
    tmp_trim="${log_file}.tmp"
    tail -c 100000 "$log_file" > "$tmp_trim" 2>/dev/null && mv "$tmp_trim" "$log_file" 2>/dev/null || true
fi

# Persist the raw response body for extraction + later inspection.
printf '%s' "$resp_raw" > "$resp_file" 2>/dev/null || true

# ── extract content / detect API errors ──────────────────────────────────────
# Empty body => network-level failure. Surface curl's stderr if we have it.
if [[ -z "$resp_raw" ]]; then
    if [[ -s "$stderr_file" ]]; then
        _cerr="$(cat "$stderr_file" 2>/dev/null)"
        emit_error "⚠️ Empty response from $provider_input_lc" "${_cerr:0:160} | Log: $log_file"
    fi
    emit_error "⚠️ Empty response from $provider_input_lc" "Network/timeout — check connection. Log: $log_file"
fi

# All three providers use the same error envelope {"error":{"message":...}}.
# Detected in the main shell so emit_error's exit actually ends the script.
api_error="$(jq -r '.error.message // empty' "$resp_file" 2>/dev/null)"
if [[ -n "$api_error" ]]; then
    emit_error "⚠️ $provider_input_lc error" "${api_error:0:200}"
fi

case "$format" in
    openai)    raw="$(jq -r '.choices[0].message.content // empty' "$resp_file" 2>/dev/null)" ;;
    anthropic) raw="$(jq -r '.content[0].text // empty' "$resp_file" 2>/dev/null)" ;;
    # Interactions API: model reply is the text in the last model_output step.
    gemini)    raw="$(jq -r '[.steps[]? | select(.type=="model_output") | .content[]? | select(.type=="text") | .text] | last // empty' "$resp_file" 2>/dev/null)" ;;
esac

if [[ -z "$raw" ]]; then
    emit_error "⚠️ Empty response from $provider_input_lc" "No content extracted. Log: $log_file"
fi

# ── parse model output ───────────────────────────────────────────────────────
# The model was asked for minified JSON. Strip accidental Markdown fences and
# keep the first {...} block.
clean="$(printf '%s' "$raw" | sed -e 's/```[a-zA-Z0-9]*//g' -e 's/```//g')"
json_obj="$(printf '%s' "$clean" | sed -n '/^{/,/}$/p' | head -n 1)"

if [[ -z "$json_obj" ]] || ! jq -e . >/dev/null 2>&1 <<<"$json_obj"; then
    printf '%s' "$raw" | head -c 800 > "$log_dir/raw-model-output.txt"
    emit_error "⚠ Malformed JSON from $provider_input" "Press ⇧ to inspect raw model output" "file://$log_dir/raw-model-output.txt"
fi

corrected="$(jq -r '.corrected // ""' <<<"$json_obj")"
changes="$(jq -r '.changes // [] | map(.)' <<<"$json_obj")"
explanation="$(jq -r '.explanation // ""' <<<"$json_obj")"

if [[ -z "$corrected" ]]; then
    emit_error "⚠ No corrected text returned" "The model returned an unexpected payload"
fi

# ── build Alfred result ──────────────────────────────────────────────────────

change_count="$(jq 'length' <<<"$changes")"

if [[ "$change_count" -eq 0 ]]; then
    change_line="✓ Already correct — no changes needed"
else
    change_line="$(jq -r 'join(", ")' <<<"$changes")"
    [[ ${#change_line} -gt 180 ]] && change_line="${change_line:0:177}..."
fi

# Persist the full explanation for Quick Look (⇧ on the note item).
note_file="$log_dir/note.md"
{
    printf '# Grammar note (%s)\n\n' "$explain_lang"
    printf '**Original:**\n\n%s\n\n' "$query"
    printf '**Corrected:**\n\n%s\n\n' "$corrected"
    if [[ "$change_count" -gt 0 ]]; then
        printf '## Changes\n\n'
        jq -r '.[] | "- \(.)"' <<<"$changes"
        printf '\n'
    fi
    if [[ -n "$explanation" ]]; then
        printf '## Explanation\n\n%s\n' "$explanation"
    fi
} >"$note_file"

# Short subtitle for the note item (first sentence of the explanation, if any).
note_short="$(printf '%s' "$explanation" | awk -F'[.!?]' '{print $1}' | head -c 140)"
[[ -z "$note_short" ]] && note_short="Press ⇧ to read the full note"

# Two-item payload: corrected text (actionable) + explanation note (info).
jq -n \
    --arg corrected "$corrected" \
    --arg change_line "Changed: ${change_line}   ·   ↵ copy" \
    --arg explanation "$explanation" \
    --arg note_short "$note_short" \
    --arg note_url "file://${note_file}" \
    '{items:[
        {
            uid:"grammar-corrected",
            title:("✏ " + $corrected),
            subtitle:$change_line,
            arg:$corrected,
            valid:true,
            text:{copy:$corrected, largetype:$corrected},
            mods:{ cmd:{arg:$explanation, subtitle:"Copy explanation instead", valid:true} }
        },
        {
            uid:"grammar-note",
            title:("💡 " + $note_short),
            subtitle:"Explanation · press ⇧ to read full note",
            valid:false,
            quicklookurl:$note_url
        }
    ]}'

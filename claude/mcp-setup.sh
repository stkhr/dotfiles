#!/bin/zsh
# MCP server setup for Claude Code (user scope).
# Re-runnable: a server that is already registered with the same command is
# skipped; one registered with a different command is removed and re-added,
# because `claude mcp add` fails on a duplicate name and has no --replace.
# Removing an http server drops its OAuth state, so notion is only touched
# when its URL changes.

CLAUDE_JSON="$HOME/.claude.json"

registered() {
    # prints "<command> <args...>" for stdio, "<url>" for http; empty if absent
    jq -r --arg n "$1" '
        .mcpServers[$n] // empty
        | if .type == "http" then .url else ([.command] + (.args // [])) | join(" ") end
    ' "$CLAUDE_JSON" 2>/dev/null
}

ensure_stdio() {
    local name="$1"; shift
    local desired="$*"
    local current
    current=$(registered "$name")
    if [[ "$current" == "$desired" ]]; then
        echo "[mcp-setup] $name: up to date"
        return
    fi
    if [[ -n "$current" ]]; then
        if ! claude mcp remove "$name" --scope user; then
            echo "[mcp-setup] $name: remove failed, not re-added" >&2
            return 1
        fi
    fi
    claude mcp add "$name" --scope user -- "$@"
}

ensure_http() {
    local name="$1" url="$2"
    local current
    current=$(registered "$name")
    if [[ "$current" == "$url" ]]; then
        echo "[mcp-setup] $name: up to date"
        return
    fi
    if [[ -n "$current" ]]; then
        if ! claude mcp remove "$name" --scope user; then
            echo "[mcp-setup] $name: remove failed, not re-added" >&2
            return 1
        fi
    fi
    claude mcp add "$name" --transport http --scope user "$url"
}

ensure_stdio serena docker run --rm -i --network host \
    -v "$HOME/ghq:/workspaces/projects" \
    ghcr.io/oraios/serena:latest \
    serena start-mcp-server \
    --transport stdio \
    --context ide-assistant \
    --project /workspaces/projects

ensure_stdio chrome-devtools npx -y chrome-devtools-mcp@1.8.0

ensure_stdio context7 npx -y @upstash/context7-mcp@4.0.4

ensure_stdio drawio npx -y @drawio/mcp@1.5.0

ensure_http notion https://mcp.notion.com/mcp

# AWS MCP Server (GA: https://aws.amazon.com/jp/blogs/aws/the-aws-mcp-server-is-now-generally-available/)
# Proxy: https://github.com/aws/mcp-proxy-for-aws (official, Apache-2.0)
# Requires: uv (https://astral.sh/uv) and configured AWS credentials (IAM SigV4 auth)
# endpoint=us-east-1 is the public regional MCP endpoint; AWS_REGION targets the actual API calls.
if command -v uvx &> /dev/null; then
    ensure_stdio aws uvx mcp-proxy-for-aws@latest \
        https://aws-mcp.us-east-1.api.aws/mcp \
        --metadata AWS_REGION=ap-northeast-1
else
    echo "[mcp-setup] skip: aws MCP requires 'uvx' (install via: brew install uv)" >&2
fi

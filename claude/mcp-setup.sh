#!/bin/zsh
# MCP server setup for Claude Code
# Run this script to register MCP servers via `claude mcp add`
# Scope: user (available across all projects)

claude mcp add serena --scope user \
    -- docker run --rm -i --network host \
    -v "$HOME/ghq:/workspaces/projects" \
    ghcr.io/oraios/serena:latest \
    serena start-mcp-server \
    --transport stdio \
    --context ide-assistant \
    --project /workspaces/projects

claude mcp add chrome-devtools --scope user \
    -- npx -y chrome-devtools-mcp@0.12.1

claude mcp add context7 --scope user \
    -- npx -y @upstash/context7-mcp@2.1.0

claude mcp add playwright --scope user \
    -- npx -y @executeautomation/playwright-mcp-server@1.0.12

claude mcp add drawio --scope user \
    -- npx -y @drawio/mcp

claude mcp add notion --transport http --scope user \
    https://mcp.notion.com/mcp

# AWS MCP Server (GA: https://aws.amazon.com/jp/blogs/aws/the-aws-mcp-server-is-now-generally-available/)
# Requires: uv (https://astral.sh/uv) and configured AWS credentials (IAM SigV4 auth)
if command -v uvx &> /dev/null; then
    claude mcp add aws --scope user \
        -- uvx mcp-proxy-for-aws@latest \
           https://aws-mcp.us-east-1.api.aws/mcp \
           --metadata AWS_REGION=ap-northeast-1
else
    echo "[mcp-setup] skip: aws MCP requires 'uvx' (install via: brew install uv)" >&2
fi

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

#!/usr/bin/env bash
# Runs once when the container is created.
set -u

npm install -g @anthropic-ai/claude-code

echo "lua:      $(lua -v 2>&1)"
echo "luacheck: $(luacheck --version 2>&1 | head -1)"
echo "stylua:   $(stylua --version 2>&1)"

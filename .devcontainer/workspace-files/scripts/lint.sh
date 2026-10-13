#!/usr/bin/env bash
# Lint + format-check every Lua file in the addon.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== luacheck =="
luacheck .

echo "== stylua --check =="
stylua --check .

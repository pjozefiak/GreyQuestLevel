#!/usr/bin/env bash
# Static analysis + a syntax check for every Lua file in the addon.
#
# Deliberately does not run `stylua --check`: StyLua reflows this file's
# hand-wrapped expressions and aligned comments even when configured to match
# its style (see stylua.toml). Formatting is not enforced here.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== luacheck =="
luacheck .

echo "== syntax (luac5.1 -p) =="
for f in *.lua; do
    luac5.1 -p "$f"
    echo "ok  $f"
done

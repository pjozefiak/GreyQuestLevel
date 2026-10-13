# WoW Addon devcontainer

Mirrors the `wow-helper` devcontainer (same `~/.claude` bind mount, same
`CLAUDE_CONFIG_DIR` / `ANTHROPIC_MODEL` env, Claude Code installed on create),
but the toolchain is Lua 5.1 instead of Python/Flask.

## Where the files go

Move the contents into your addon repo like this:

```
MyAddon/
├── .devcontainer/
│   ├── devcontainer.json
│   ├── devcontainer-lock.json
│   ├── Dockerfile
│   ├── post-create.sh
│   └── README.md           (this file, optional)
├── .editorconfig           (from workspace-files/)
├── .luacheckrc             (from workspace-files/)
├── .luarc.json             (from workspace-files/)
├── stylua.toml             (from workspace-files/)
├── scripts/
│   ├── lint.sh             (from workspace-files/scripts/)
│   └── package.sh          (from workspace-files/scripts/)
├── MyAddon.toc
└── MyAddon.lua
```

So: this folder's four config files → `.devcontainer/`, everything under
`workspace-files/` → the addon root.

## What's in the image

| Tool | Purpose |
| --- | --- |
| `lua5.1` (also on PATH as `lua`) | same Lua version the WoW client embeds |
| `luacheck` | static analysis, configured with WoW globals in `.luacheckrc` |
| `stylua` | formatter, format-on-save via the VS Code extension |
| `node` 20 + `@anthropic-ai/claude-code` | same as the Flask container |

VS Code extensions come preconfigured too: `sumneko.lua` (language server, pinned
to Lua 5.1), `ketho.wow-api` (API/`Enum`/frame-method completion and `.toc`
support — it feeds its annotations to the language server itself), plus the
StyLua, luacheck and EditorConfig integrations.

## Live-reloading into a real WoW install

Uncomment the second mount in `devcontainer.json` and set `WOW_ADDONS_PATH` on
the **host** before opening the container:

- macOS: `/Applications/World of Warcraft/_retail_/Interface/AddOns`
- Windows: `C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns`

```bash
# macOS / Linux host
export WOW_ADDONS_PATH="/Applications/World of Warcraft/_retail_/Interface/AddOns"
```

Then `./scripts/package.sh --deploy` copies the addon into `/wow-addons` and you
`/reload` in game. Without the mount, `package.sh` still builds
`dist/MyAddon-<version>.zip` from the `## Version:` line in the `.toc`.

## Day-to-day

```bash
./scripts/lint.sh          # luacheck + stylua --check
stylua .                   # format everything
./scripts/package.sh       # build the release zip
```

## Notes

- Add every saved variable from your `.toc` to the `globals` list in
  `.luacheckrc` (the placeholders are `MyAddonDB` / `MyAddonCharDB`), otherwise
  luacheck flags them as accidental globals.
- Vendored libraries (`Libs/`, `libs/`) are excluded from linting on purpose.
- `.luarc.json` sets `format.enable: false` so the Lua language server doesn't
  fight StyLua over formatting.

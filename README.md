# Gray Quest Level

Shows on screen which quest levels are still green and where they turn gray.

## Install

Drop the `GrayQuestLevel` folder into:

```
World of Warcraft/_classic_beta_/Interface/AddOns/GrayQuestLevel/
```

(`_retail_` works too — the TOC lists both interface numbers.) Then `/reload`
or restart the client. Note the addon "Reload UI" button is protected on the
Forever beta, so type `/reload` rather than clicking anything.

## Use

A small draggable box appears near the top of the screen:

```
Green 23+  -  Gray 22-
Kills to level: 15
```

Drag it anywhere. Commands:

- `/gql` — print the numbers to chat and list the commands
- `/gql lock` — stop it being dragged
- `/gql reset` — put it back at the top
- `/gql hide` / `/gql show`
- `/gql xp <n>` — seed the per-kill XP by hand instead of waiting for a gain
- `/gql calibrate <n>` — you see level `n` greyed out in your log; shift to match
- `/gql debug` — print both boundary sources and what each API returns
- `/gql source <auto|range|colors>` — pick which source to trust

## How the boundary is worked out

Two sources, and on the Forever beta they don't always agree:

- **range** (default) — `playerLevel - UnitQuestTrivialLevelRange("player")`
- **colors** — walk `GetQuestDifficultyColor` down until it reports trivial

`/gql debug` prints both and flags a disagreement. `/gql source range|colors|auto`
picks one; whichever matches your quest log is the right one.

Note the arithmetic is `level - range`, *not* `level - range - 1`. Retail's own
`GetQuestDifficultyColor` compares `-levelDiff <= range`, which implies the extra
`-1`; this client behaves as though the comparison is `>=`. Measured at level 8:
range 5, quest log greys out level 3.

`GetQuestDifficultyColor` was the default in v1.2, on the reasoning that it's the
function the quest log colours with. That was dropped in v1.4 because on this
build it returned the same boundary at level 8 and at level 9 — it didn't move
when the character levelled, while the arithmetic did. It's still available via
`/gql source colors` in case that turns out to be the accurate one.

## Forever beta notes

- Saved position won't survive a logout. The beta writes `SavedVariables` on
  exit but never reads them back (a known client bug), so the box returns to
  its default spot each launch. Nothing to fix addon-side; it'll start working
  when Blizzard fixes the client.
- Event registration is wrapped in `pcall`, because registering an event the
  client doesn't know throws and aborts the whole file on this build.
- No secure snippets, no combat data, no aura reads — this is a display-only
  reference addon, so none of the Midnight-era restrictions apply to it.

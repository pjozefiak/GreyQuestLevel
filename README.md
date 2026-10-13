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
Stored EXP: 700  (grinding)
Green 23+  -  Gray 22-
Kills to level: 15
```

The first row only appears while you owe stored EXP — see the challenge below.
Drag it anywhere; **the position is saved per character**, so characters running
different UIs can each keep the box somewhere sensible. Commands:

- `/gql` — print the numbers to chat and list the commands
- `/gql lock` — stop it being dragged
- `/gql reset` — put it back at the top
- `/gql hide` / `/gql show`
- `/gql xp <n>` — seed the per-kill XP by hand instead of waiting for a gain
- `/gql calibrate <n>` — you see level `n` greyed out in your log; shift to match
- `/gql debug` — print every boundary source and what each API returns
- `/gql source <auto|table|range|colors>` — pick which source to trust
- `/gql chat` — list the chat windows; `/gql chat <n>` sends the addon's output
  to window `n`, `/gql chat default` puts it back
- `/gql options` — open the options panel

Challenge commands:

- `/gql grind` — toggle grinding mode: XP you earn pays off the stored EXP
- `/gql exp <+/-n>` — adjust the stored EXP by hand (`/gql exp -767` removes 767)
- `/gql quest <n>` — the quest you just handed in was really worth `n`; stores
  the shortfall against what it actually paid, for that hand-in only
- `/gql xpdb` — how many entries `QuestXP.lua` holds; `/gql xpdb <questID>`
  looks one up

## Where the addon prints

By default everything goes to the default chat window. To send it somewhere
else — a dedicated tab, say — either use `/gql chat <n>`, or pick a window from
the dropdown in **Esc → Options → AddOns → Gray Quest Level**. The choice is
saved per character, since chat layouts are per character.

`/gql chat` with no argument lists the windows it can see and marks the current
one. If the window you chose is later closed, output falls back to the default
one rather than vanishing.

The options panel is a convenience, not a requirement: it needs
`Settings.RegisterCanvasLayoutCategory` (patch 10.0) and ideally the 11.0
dropdown templates, and on a build that lacks them the panel simply is not
registered — `/gql chat` does the same job. `/gql debug` reports whether it
registered.

## The levelling challenge

Handing in a gray quest should cost you. The XP the quest would have paid at
level, minus the reduced amount it actually paid, becomes **Stored EXP** — a
debt you work off by grinding before the quest counts.

Stored EXP is **per character**. Turn on `/gql grind` and every XP gain comes
off the debt; the XP from the hand-in itself does not, since that is what
created the debt in the first place.

The un-reduced quest value cannot be read from the API.
`GetQuestLogRewardXP()` returns the already-reduced amount and
`QUEST_TURNED_IN` reports what was actually granted; the pre-reduction figure
is never exposed, and the reduction curve is not documented well enough to
invert safely. So the addon keeps its own table of full quest values.

### QuestXP.lua

Full quest values live in `QuestXP.lua`, maintained by hand:

```lua
GrayQuestLevelQuestXP = {
    [437] = 1050,
    [2137] = 767,
}
```

Wowhead lists the XP, and the quest ID is in the URL
(`.../forever/quest=437/the-dead-fields` → `437`). The file is read at load, so
**edits need a `/reload`** before they take effect. `/gql xpdb` reports how many
entries it holds and `/gql xpdb <questID>` looks one up.

### Importing a zone

Rather than typing a zone out, save its Wowhead quest list and import it:

1. Open the zone's quest list on Wowhead, e.g.
   `https://www.wowhead.com/forever/zone=130/silverpine-forest` → Quests tab.
2. Save the page (Ctrl+S, "complete" or "HTML only") into `wowhead-dump/`.
3. Run the importer:

```bash
lua5.1 scripts/import-questxp.lua "wowhead-dump/Forever Silverpine Forest Quests.html"
lua5.1 scripts/import-questxp.lua wowhead-dump/*.html      # re-import every saved zone
lua5.1 scripts/import-questxp.lua --dry-run <file>         # report, change nothing
```

It works entirely offline — it only reads the files you point it at and never
contacts Wowhead. Values already in `QuestXP.lua` are never overwritten; a
disagreement is reported for you to check. Running it twice changes nothing, so
re-importing everything is always safe.

Entries are grouped by zone, with a header naming it:

```lua
GrayQuestLevelQuestXP = {
    -- Silverpine Forest (zone 130)
    [99] = 1350,  -- Arugal's Folly (15)
    [421] = 840,  -- Prove Your Worth (10)

    -- Hillsbrad Foothills (zone 267)
    [508] = 1450,  -- Bring Me Tharlidun (21)
}
```

Zones keep the order they were first imported and new ones are appended, so
adding a zone never reshuffles the existing file. The zone name and ID come
from the page itself, not the filename, so renaming a dump is harmless. Within
a zone, entries are sorted by quest ID.

The zone headers are structural: the importer reads them back to decide where
each entry belongs, so keep the `-- <Zone> (zone <id>)` format if you add a
group by hand. A quest listed under two zones (breadcrumbs often are) stays in
the first zone that claimed it, and the second is reported.

Keeping the saved pages around is optional — the values live in `QuestXP.lua`
once imported. They are gitignored, so they stay on your machine and are never
shipped in the release zip.

Nothing is ever written back. A quest value is either in that file or it isn't,
and the addon never saves one behind your back.

### Handing in a gray quest

If the quest is in the file, the debt is worked out and added to the character's
stored EXP with no input from you:

```
Gray Quest Level: gray quest (level 10): 900 full - 300 paid = 600 stored.
  Stored EXP now 600.
```

If it isn't, the addon says so — this is the only prompt it ever gives, and it
is your cue to add the entry:

```
Gray Quest Level: gray quest 503 (level 10) paid 250 XP - not in QuestXP.lua.
  Add [503] = <full XP> to QuestXP.lua (then /reload), or /gql quest <full XP> to count it now.
```

`/gql quest <n>` credits that one hand-in immediately, so you don't have to stop
and edit a file mid-session, and it echoes the entry to add later. It does not
save anything.

Note the addon cannot read JSON, or any other file it is not told to load: the
WoW Lua sandbox has no file I/O, so data has to be a `.lua` file listed in the
`.toc`.

### By hand

`/gql exp <+/-n>` adjusts the debt directly, for anything the addon cannot work
out for itself. The debt clamps at zero and never goes negative.

## How the boundary is worked out

Three sources, and on the Forever beta they don't agree:

- **table** (default) — the published vanilla gray-level table
- **range** — `playerLevel - UnitQuestTrivialLevelRange("player")`
- **colors** — walk `GetQuestDifficultyColor` down until it reports trivial

`/gql debug` prints all three and flags any that disagree with the table.
`/gql source table|range|colors|auto` picks one; whichever matches your quest
log is the right one.

The table is:

| Player level | Highest gray level |
| --- | --- |
| 1–5 | nothing is gray |
| 6–39 | `level - floor(level/10) - 5` |
| 40–59 | `level - floor(level/5) - 1` |
| 60+ | `level - 9` |

Both client APIs are wrong here, which is why neither is the default any more.
`UnitQuestTrivialLevelRange` returns a flat **5** on this build — Retail's
non-scaling value — where vanilla scales it with level. The level-8 reading that
made `range` the default in v1.4 agreed only by coincidence: `floor(8/10)` is 0,
so the missing term happened not to matter at that level.

Measured at level 20: `range` said gray 15, `colors` said gray 14, and the quest
log showed a level-14 quest ([The Dead Fields][dead-fields]) still green,
turning gray at 21. That is gray 13 — `20 - floor(20/10) - 5`, the table, and
neither API.

[dead-fields]: https://www.wowhead.com/forever/quest=437/the-dead-fields

Only the 6–39 band is confirmed against this client (at levels 8 and 20). The
40+ bands are the published vanilla formulas and are unverified here; note they
are not continuous at 60 (level 59 gives gray 47, level 60 gives 51), which is
how the tables are written. If the display disagrees with your quest log at
those levels, `/gql debug` shows every source and `/gql calibrate <n>` applies
an offset.

`GetQuestDifficultyColor` was the default in v1.2, on the reasoning that it's
the function the quest log colours with. It was dropped in v1.4 because on this
build it returned the same boundary at level 8 and at level 9 — it didn't move
when the character levelled. It is still available via `/gql source colors`.

## Forever beta notes

- `SavedVariables` round-trip correctly now. Earlier builds wrote them on exit
  but never read them back, so the box returned to its default spot each
  launch; that is fixed client-side. Source and offset are account-wide; the box
  position and the challenge state are per character.
- Event registration is wrapped in `pcall`, because registering an event the
  client doesn't know throws and aborts the whole file on this build.
- No secure snippets, no combat data, no aura reads — this is a display-only
  reference addon, so none of the Midnight-era restrictions apply to it.

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
Drag it anywhere. Commands:

- `/gql` — print the numbers to chat and list the commands
- `/gql lock` — stop it being dragged
- `/gql reset` — put it back at the top
- `/gql hide` / `/gql show`
- `/gql xp <n>` — seed the per-kill XP by hand instead of waiting for a gain
- `/gql calibrate <n>` — you see level `n` greyed out in your log; shift to match
- `/gql debug` — print every boundary source and what each API returns
- `/gql source <auto|table|range|colors>` — pick which source to trust

Challenge commands:

- `/gql grind` — toggle grinding mode: XP you earn pays off the stored EXP
- `/gql exp <+/-n>` — adjust the stored EXP by hand (`/gql exp -767` removes 767)
- `/gql quest <n>` — the quest you just handed in was really worth `n`; stores
  the shortfall against what it actually paid

## The levelling challenge

Handing in a gray quest should cost you. The XP the quest would have paid at
level, minus the reduced amount it actually paid, becomes **Stored EXP** — a
debt you work off by grinding before the quest counts.

Stored EXP is **per character**. Turn on `/gql grind` and every XP gain comes
off the debt; the XP from the hand-in itself does not, since that is what
created the debt in the first place.

The un-reduced quest value cannot be read from the API, so you supply it.
`GetQuestLogRewardXP()` returns the already-reduced amount and
`QUEST_TURNED_IN` reports what was actually granted; the pre-reduction figure
is never exposed, and the reduction curve is not documented well enough to
invert safely. So when you hand in a gray quest the addon tells you what it
paid, and you look the quest up (Wowhead) and type the real number:

```
Gray Quest Level: gray quest (level 10) paid 350 XP.
  The API has no un-reduced value - /gql quest <full XP> to store the difference.

/gql quest 1050
Gray Quest Level: 1050 full - 350 paid = 700 stored (total 700).
```

`/gql exp <+/-n>` is there for anything the addon cannot work out for itself.
The debt clamps at zero and never goes negative.

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
  launch; that is fixed client-side, and position, source, offset and the
  challenge state all persist.
- Event registration is wrapped in `pcall`, because registering an event the
  client doesn't know throws and aborts the whole file on this build.
- No secure snippets, no combat data, no aura reads — this is a display-only
  reference addon, so none of the Midnight-era restrictions apply to it.

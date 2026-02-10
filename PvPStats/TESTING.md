# PvPStats — In-Game Testing Guide

## Setup

1. Symlink or copy the `PvPStats/` folder into your WoW AddOns directory:
   ```
   World of Warcraft_ANNIVERSARY_/Interface/AddOns/PvPStats/
   ```
2. Log in, check AddOns button at character select — PvPStats should appear
3. On login you should see: `[PvPStats] v0.1.0 loaded. Type /pvpstats to open.`

## Quick Smoke Tests

### Slash commands
- `/pvpstats` — should open the tracker window (empty on first run)
- `/pvpstats count` — should print `0 match(es) recorded.`
- `/pvpstats reset` — clears all data

### API Verification (run in /dump before your first BG)

These need in-game verification to confirm they work in TBC 2.5.x:

```
/dump GetMaxBattlefieldID()
/dump GetBattlefieldStatus(1)
/dump IsInGroup()
/dump UnitFactionGroup("player")
/dump GetServerTime()
```

## BG Test Flow

### 1. Queue phase
- Queue for a BG (solo or with group)
- Expected: `[PvPStats] Queued for Warsong Gulch (solo)` (or group)
- Verify solo/group detection is correct

### 2. BG active phase
- Enter the BG when it pops
- Expected: `[PvPStats] Warsong Gulch started.`

### 3. BG end phase
- Play until the BG finishes (win or loss)
- Expected: `[PvPStats] WSG Win | 12m 34s | 5 KB`
- Run `/pvpstats` to verify the match appears in the list
- Click a match row to see the full scoreboard detail

### 4. Abandoned BG
- Queue and enter a BG, then leave early
- Expected: `[PvPStats] WSG Left`

## Things That Need Verification

These API behaviors are based on documentation but haven't been tested in TBC 2.5.x:

1. **GetBattlefieldScore() return values** — Does it return `faction`, `race`, `class`, `classToken` fields? If not, scoreboard roster will be missing class/faction data.

2. **LE_PARTY_CATEGORY_HOME constant** — Does it exist? If not, the fallback to `IsInGroup()` without args should work, but solo/group detection in edge cases (like being in a group for non-BG reasons) could be wrong.

3. **GetBattlefieldStatInfo() iteration** — Does it return nil for invalid indices, or does it error? The code assumes nil return terminates the loop.

4. **BasicFrameTemplateWithInset** — Does `f.InsetBg` exist on this template in TBC Classic? The code has `or parent` fallbacks.

5. **FauxScrollFrameTemplate** — Should exist in TBC Classic since it's a core Blizzard template, but verify scroll behavior works.

6. **GetBattlefieldWinner()** — Verify it returns 0/1/255/nil as expected.

7. **Scoreboard timing** — After `GetBattlefieldWinner()` returns non-nil, is the full scoreboard data immediately available, or do we need an additional `RequestBattlefieldScoreData()` call?

## Debugging

If something isn't working:
- `/etrace` — watch for `UPDATE_BATTLEFIELD_STATUS` and `UPDATE_BATTLEFIELD_SCORE` events
- `/dump GetBattlefieldStatus(1)` — check current BG status
- `/dump GetNumBattlefieldScores()` — verify scoreboard has data
- `/dump GetBattlefieldScore(1)` — check what fields come back
- `/dump GetBattlefieldWinner()` — check if BG is detected as over

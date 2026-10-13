# DotGrid

A bar / grid that shows **how much of the mobs in melee range carry the debuff(s) you watch** — expressed as *length*, not as a number.

**English** | [简体中文](README.zh-CN.md)

> Since 12.x, aura data is unreadable for addons while you are in combat, so "what share of the mobs
> have my DoT" cannot be shown as a number. DotGrid's answer: **one segment per mob — the length of
> the bar is the mob count, the red part is the ratio.** You read it with your eyes.

<!-- Screenshot: drop a picture at docs/images/preview.png (and an optional docs/images/preview.gif)
     and uncomment the next line. -->
<!-- ![DotGrid](docs/images/preview.png) -->

## Features

- Bar or grid display; the length always follows the mob count (no empty segments)
- Watch up to 4 debuffs at once: all-applied (default) or any-hit semantics
- Three looks: flat colour / client panel / client nameplate (no custom textures at all)
- Drag to position, live preview, opaque-alpha sliders; every command is also a button
- Account-level profiles: one per character, create / switch / delete at any time
- No third-party libraries, no Blizzard UI templates, no custom textures, no files written, no network
- Ships with an offline test suite — no game client needed

## Requirements

- World of Warcraft **Retail 12.1 (Midnight)**, interface version `120100`
- Any client locale; Simplified Chinese by default, English UI strings included (`Locales/enUS.lua`)

## Installation

**From a release (recommended)**

1. Download `DotGrid-<version>.zip` from the [Releases](../../releases) page
2. Extract it into `<World of Warcraft>/_retail_/Interface/AddOns/` so that you end up with
   `Interface/AddOns/DotGrid/DotGrid.toc`
3. Restart the client and make sure **DotGrid** is ticked in the AddOns list

**From source (git)**

```bash
git clone https://github.com/blacklc/DotGrid.git
cp -r DotGrid/DotGrid "<World of Warcraft>/_retail_/Interface/AddOns/"
```

Windows users can create a directory junction instead of copying, so the game always runs the
checked-out code:

```cmd
mklink /J "C:\...\Interface\AddOns\DotGrid" "D:\DotGrid\DotGrid"
```

## How to use

The addon does **nothing at all until you tell it which debuff to watch** — that is the idle state:
no scanning, no geometry, nothing drawn.

```
/dg spell 1943,703     watch these spell IDs (comma or space separated, up to 4)
/dg unlock             the display area turns into a yellow box you can drag
/dg lock               lock it again (the position is saved)
/dg bar min 1          show the bar even with a single mob
/dg                    open the settings window (press again or Esc to close)
```

Then walk into a pack of mobs:

- **bar**: one segment per mob. A white segment = a mob in range without your debuff, a **red**
  segment = that mob carries it. So "3 of 8 mobs" looks like a short red stub on a longer white bar.
- **grid**: one cell per mob, same colours.
- With several watched spells and `all` semantics, each cell is split into one band per spell —
  the whole cell turns red only when every spell is applied.

Read the exact counts (and per-mob coordinates) with `/dg diag`; `/dg help` lists every command plus
the current state.

## Commands

`/dg` with no argument opens the settings window (`/dg config`, `ui`, `options` are aliases; closing
works with the same key or Esc). `/dg help` prints all commands and the current state.

| Command | Description |
| --- | --- |
| `/dg` | open the settings window (press again to close) |
| `/dg help` | every command + current state |
| `/dg on` / `off` | enable / disable |
| `/dg mode bar` / `grid` | display: bar (default) / grid |
| `/dg style solid` / `panel` / `nameplate` | look: flat colour (default) / panel / nameplate |

**Bar**

| Command | Description |
| --- | --- |
| `/dg bar segw 21` | segment width 6–60 (total = mobs × (segw + gap) − gap) |
| `/dg bar min 2` | hide the whole bar below this many mobs (default 2; `1` = show with one mob) |
| `/dg bar height 20` | bar height 6–80 |
| `/dg bar gap 1` | gap between segments 0–10 |
| `/dg bar ticks on` / `off` | 1px tick line between segments (default on) |

**Position**

| Command | Description |
| --- | --- |
| `/dg unlock` / `lock` | unlock dragging / lock again |
| `/dg pos` | show the current position |
| `/dg pos 800 500` | set the position (x y, from the screen's bottom-left corner) |
| `/dg pos center` | back to the default centre-left position |

**Watched debuffs** (spell IDs only, up to 4)

| Command | Description |
| --- | --- |
| `/dg spell 1943,703` | set the watched spell IDs |
| `/dg spell clear` | clear the list → the addon goes idle |
| `/dg spells` | show the watched spells and the multi-debuff semantics |
| `/dg spells all` / `any` | `all` = every spell must be applied (default) / `any` = any hit turns it red |

**Range and criteria**

| Command | Description |
| --- | --- |
| `/dg yards 11` | exact distance limit in yards; falls back to tiers inside instances; `0` = tiers only |
| `/dg tier 2` / `3` / `0` | tier fallback: `2` = 8yd, `3` = 7yd; `0` = no distance test (widest) |
| `/dg engaged combat` / `threat` / `all` | scope: in combat (default) / fighting you / everything in range |
| `/dg engaged on` / `off` | shorthand: `on` = combat, `off` = all |
| `/dg combat on` / `off` | only show while you are in combat (default on) |

**Grid**

| Command | Description |
| --- | --- |
| `/dg size 18x18` | cell size |
| `/dg perrow 5` | cells per row |
| `/dg gap 4` | cell gap |

**Colours and alpha**

| Command | Description |
| --- | --- |
| `/dg color hit d80f0fff` | hit colour (red segment / cell); the last two digits are alpha |
| `/dg color mob ffffffff` | mob in range without your debuff |
| `/dg color empty ffffff2e` | track / empty slot colour |
| `/dg color miss ffffffff` | grid mode: mob without your debuff |
| `/dg alpha 50` | all at once: hit / mob / cell = 50% (the track is left alone) |
| `/dg alpha hit 50` | single key: `hit` / `mob` / `miss` / `empty`, 0–100 |

**Profiles**

| Command | Description |
| --- | --- |
| `/dg profile` | list every profile (marks the one this character uses) |
| `/dg profile new <name>` | snapshot the current settings as a new profile and switch to it |
| `/dg profile load <name>` | switch this character to that profile |
| `/dg profile save` | write the current settings back to the current profile |
| `/dg profile delete <name>` | delete a profile (the default one and the one in use are protected) |
| `/dg reset` | factory reset (current profile only) |

**Diagnostics**

| Command | Description |
| --- | --- |
| `/dg diag` | environment self-check: geometry, range verdicts with raw returns, per-mob state, UI state |
| `/dg verify` | out-of-combat truth check: per mob, prints which spells are up and which segment it is |
| `/dg debug on` / `off` | debug output |

Older commands from removed features (`bar fixed`, `bar width`, `label`, `mode pie`, …) only print a
notice and change nothing.

## Settings window

Opened with `/dg`. The window itself is draggable (its position is stored in the save file); eight
pages:

| Page | Contents |
| --- | --- |
| General | preview canvas / enable switch / display / look / in-combat only / unlock·lock / position sliders |
| Watched debuffs | add and remove spell IDs, multi-debuff semantics, "Clear spells (idle)" |
| Bar | preview canvas / segment width / height / gap / minimum mobs / ticks |
| Grid | preview canvas / cell width, height / cells per row / gap |
| Colours | preview canvas / four alpha sliders (live preview) / four swatches |
| Range | scope / exact yard limit / tier fallback |
| Tools | self-check / truth check / factory reset / print help / debug output |
| Profiles | current profile / save / delete / name box / new / load / profile list |

The window holds **no logic of its own**: every control builds a command string and hands it to
SlashCmdList, which also echoes it to chat — so the UI and the command line can never drift apart.

## Display and looks

**Bar** (`/dg mode bar`, default): one segment per mob — width `bar segw` (default 21), gap `bar gap`
(default 1), height `bar height` (default 20); total = mobs × (segw + gap) − gap. With a very large
pack (over 900 px) the segment width is squeezed down to 4 px minimum so no mob is dropped.

**Grid** (`/dg mode grid`): one cell per mob (18×18 by default, 5 per row).

**Looks** (`/dg style`):

| Setting | Description |
| --- | --- |
| `solid` (default) | bar, cells, track and outline are drawn by the addon; no textures |
| `panel` | the whole block uses the client's tooltip panel; fills use the client's status-bar texture |
| `nameplate` | border tinted gold from the tooltip border texture; fills use the nameplate bar texture |

The two client-look modes drop the addon's own 1px outline to avoid a double border. Only client
built-ins are used: `Interface\Tooltips\UI-Tooltip-Background`, `Interface\Tooltips\UI-Tooltip-Border`,
`Interface\Tooltips\Nameplate-Border`, `Interface\TargetingFrame\UI-StatusBar`,
`Interface\TargetingFrame\NameplateFill`.

Defaults: hit `#d80f0f`, mob and cell plain white, track white 18%; the outline is fixed at black 55%
and the tick lines at black 60%. Four alpha sliders (0–100%) control transparency separately.

## Range and criteria

The client exposes only two distance APIs, and there is no 11-yard tier:

| Criterion | Description |
| --- | --- |
| `UnitDistanceSquared` | the only API that yields real yards; restricted in instances / arenas / battlegrounds, where the addon falls back to tiers |
| `CheckInteractDistance` | fixed tiers only: `1` = 28yd, `2` = 8yd, `3` = 7yd, `4` = 28yd, `5` = 7yd |

The two criteria are combined by taking the **stricter** one, so the defaults (`/dg yards 11` +
`/dg tier 2`) come out as 8 yards. To tighten the range: `/dg yards 5`, `/dg tier 3`, or
`/dg engaged threat` (usually the most effective). `/dg yards 0` = tiers only, `/dg tier 0` = no
distance test at all (range = nameplate visibility). How far nameplates are shown is a client CVar
and unrelated to the addon: `/console nameplateMaxDistance 10`.

Scope: `combat` counts anything in combat (default); `threat` requires it to be fighting you or your
party (`UnitThreatSituation`, degrading to the combat test per mob where restricted); `all` counts
everything in range.

## Profiles and multiple characters

The save file is account-wide (`DotGridDB`) and holds `profiles[<name>]` plus
`charProfile[<character>]`.

A character that has never been assigned a profile gets a fresh profile named after itself on first
load — it does **not** inherit the default profile, so it also does not inherit somebody else's
spells, and the addon stays idle until you set one. On upgrade, the character that was present when
the new version first ran adopts the migrated legacy settings, so existing users keep their setup.

Reads are "current profile ∪ factory defaults"; every write goes to the current profile. For a
character-specific set: `/dg profile new <name>`.

## Diagnostics

```
/dg diag      environment self-check: geometry, range verdicts and raw returns, per-mob state
              (attackable / dead / in combat / threat / distance / tier), segment coordinates and
              the client texture, UI state
/dg verify    out-of-combat truth check: aura data is readable then, so it prints per mob which
              spells are up and which segment it maps to
/dg debug on  debug output ([DBG] / [A] / [1] / [2] / [3] prefixes)
```

## How it works

Aura data in combat is *secret* to addons: it cannot be read or compared, so summing "mobs carrying
my debuff" into one number is impossible client-side. A bar or grid is the most a legal addon can do:
the **meaning** of the colours is decided by the client (the addon never learns the answer), the
**geometry** is decided by the addon — together they let you read the ratio as length or area.

The three steps, which are the same ones community addons with this idea use:

1. Each qualifying mob gets a rectangle that belongs to the addon (its own texture, freely writable)
2. For every mob an AuraContainer is created declaring "this slot accepts only spell N cast by *me*
   (or my pet)"; whether it shows is decided entirely by the client's aura system
3. The addon only watches its own red segments appear and disappear — computing is reduced to
   looking at colours

Therefore: never read AuraButton members, never listen to `UNIT_AURA`, never anchor a container to
somebody else's frame.

## FAQ

**Nothing appears on screen**
Set a spell first (`/dg spell 1943,703`) — with no watched debuff the addon is idle. Then check
"In combat only" (on by default) and that at least 2 mobs are in range (`/dg bar min 1` allows a
single mob).

**No red segment ever shows**
Run `/dg verify` out of combat to compare per mob, or `/dg debug on` for a fight and look for
`AddAuraSlot` failures or a missing fill texture in `initializeFrame`.

**I cannot drag it where I want**
`/dg unlock` then drag the yellow box; its top-left corner is the coordinate origin. While locked the
addon registers no mouse events, so it cannot block other addons.

**The settings window is blank on the right**
`/reload` and open it again; if it is still blank, run `/dg diag` and read the last line
(`UI: window=… page=… rows=…`): 0 rows means the window was not built, 0 visible rows means the page
name went stale. Build or refresh errors are printed straight to chat.

**I want to count only what is actually fighting me**
`/dg engaged threat`. Where threat is restricted (instances, PvP) a mob falls back to the combat
test.

## Technical notes (for contributors)

- Only documented primitives are used: `UnitExists`, `UnitCanAttack`, `UnitIsDead`,
  `UnitAffectingCombat`, `CheckInteractDistance`, `UnitDistanceSquared`, `UnitThreatSituation`. The
  two that may be restricted (distance, threat) are always called through `pcall` plus an
  `issecretvalue` pre-check and degrade to the more conservative criterion — never to a wider range.
- Size and colour can only be set once, inside `initializeFrame`; changing them goes through
  `RebuildRecords()`, which retires and rebuilds the whole batch (effective immediately, no `/reload`).
  Order changes only need `SetPoint`.
- There is exactly one meaning of "segment count": `BarCount()` = the number of mobs currently in
  range. Do not introduce a second source.
- Fewer than `BarMin()` mobs take the early `HideAllVisuals()` exit: bar, track, tick lines and the
  client-side aura containers are all disabled together.
- With no watched spell the refresh path returns early (idle), and `RebuildRecords()` guards again —
  several commands rebuild before they refresh.
- The unlock anchor is stretched, so every texture on it must use explicit coordinates plus `SetSize`;
  never anchor with `SetAllPoints`-style calls.
- Anything in `DotGridUI.lua` must go through `API.Run("command string")`; never write to the save
  file or refresh directly from the UI, or the two will drift apart.
- Rows that carry explanation text: the control occupies −4…−24 and the text starts at −26 (the row
  height grows with `FontString:GetStringHeight`). Pages and rows are built lazily on the first `/dg`.

## Localization

Source text uses the **Chinese original as the key**; language tables live in `Locales/`:

```
Locales/enUS.lua    English (loaded on enUS / enGB clients)
```

- With no file for a locale, the Chinese original is shown as-is — adding a language needs no code change
- To add one: copy `Locales/enUS.lua` to `Locales/deDE.lua`, change the `GetLocale()` guard and the
  translations, then add one line to `DotGrid.toc`
- Keys must match the source text **character for character** (spaces and punctuation included)
- Stored data (profile names, spell IDs) is never translated; only UI and chat text goes through the
  table. The `默认` (default) profile is displayed as `default` on English clients but stays `默认`
  in the save file, so profiles cannot get mixed up

Translations are very welcome.

## Contributing

- Bug reports: include the output of `/dg diag`, the state header from `/dg help`, and what you were
  doing when it went wrong
- Read the **How it works** and **Technical notes** sections before changing code — a few of those
  constraints, when broken, make the addon fail silently in game
- Run the offline test suite before opening a pull request: see [CONTRIBUTING.md](CONTRIBUTING.md)
  and [CHANGELOG.md](CHANGELOG.md) for the project layout and history

## License

MIT — see [LICENSE](LICENSE). Use, modify and redistribute freely, including in closed-source
projects; just keep the copyright and licence notice.

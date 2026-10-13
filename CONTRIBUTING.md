# Contributing to DotGrid

Thanks for taking a look. This addon is small on purpose: five shipped code/metadata files, no
third-party libraries, no Blizzard UI templates, no custom textures. Please keep it that way.

## Project layout

```
DotGrid/                 the addon itself — this folder is what users install
  DotGrid.toc            interface version, metadata, file list (load order matters)
  DotGrid.lua            state, save-data migration, aura containers, all commands
  DotGridUI.lua          the self-drawn settings window (a pure command forwarder)
  DotGrid.xml            the AuraButton template and the fill texture definition
  Locales/enUS.lua       English UI text (keys are the Chinese originals)
  README.md              user documentation, shipped inside the addon
  LICENSE
tests/                   offline test suite (Python + lupa, no game client needed)
README.md                English project page (this repository's front page)
README.zh-CN.md          Chinese project page
CHANGELOG.md             version history
```

Anything that is not part of the addon must stay *outside* `DotGrid/`: the game loads the folder as
shipped, and users unpack it straight into `Interface/AddOns/`.

## Development loop

Point the game at your checkout instead of copying files around. On Windows:

```cmd
mklink /J "C:\...\World of Warcraft\_retail_\Interface\AddOns\DotGrid" "D:\DotGrid\DotGrid"
```

On Linux/macOS:

```bash
ln -s /path/to/DotGrid/DotGrid "$WOW/_retail_/Interface/AddOns/DotGrid"
```

Then `/reload` in game after every edit. A syntax error in a Lua file makes the whole addon fail to
load — the client will say so in the AddOns list.

## Running the tests

The suite loads the real files through a Lua interpreter with a small WoW API stub, so it needs no
game client.

```bash
pip install lupa                 # or: uv run --with lupa python tests/run_tests.py
python tests/run_tests.py        # uses ./DotGrid by default
DOTGRID_ADDON_DIR=/path/to/Interface/AddOns/DotGrid python tests/run_tests.py
```

It reports `PASS 数: … / ALL PASS` and exits non-zero on any failure. What it covers:

- Lua syntax of every shipped file, and that the toc lists exactly the files that exist
- Static hygiene: no absolute paths, no leftover symbols of removed features, no release versions or
  developer phrasing in shipped text, and no user-visible literal that bypasses the language table
- The language table must cover every key used and contain no Chinese in its values
- Behaviour, through the stub: idle state with no spell configured, command handling for display /
  look / range / alpha / profiles / reset, save-data migration from earlier versions, and the
  settings window building every page
- An end-to-end English-client run (`GetLocale()` forced to `enUS`) that must produce Chinese-free
  user-visible output

If you add or change user-visible behaviour, add a check for it. A test that cannot fail is worse
than no test — every scan in this suite carries a self-check so it cannot silently stop matching.

## Rules that are easy to break

The README explains the reasoning; the short version:

- Never read aura data and never listen to `UNIT_AURA`. The client's `AuraContainer` decides whether
  a mob carries your debuff; the addon only observes its own geometry.
- Anything that may be restricted in combat (distance, threat) goes through `pcall` and an
  `issecretvalue` pre-check, and degrades to the *more conservative* criterion.
- Size and colour can only be set inside `initializeFrame`; changing them means rebuilding through
  `RebuildRecords()`.
- The segment count has exactly one source: `BarCount()` (the current number of mobs in range).
- The settings window performs no logic of its own — every control builds a `/dg` command string.
- No absolute paths, no custom textures, no third-party libraries, no files written at runtime.
- New user-visible text goes through `L["…"]`, and the matching entry goes into every file in
  `Locales/` (keys must match the source text exactly).

## Pull requests

1. Keep the change focused; one topic per pull request
2. Run the suite (`python tests/run_tests.py`) and make sure it passes
3. If you changed behaviour, update `README.md`, `README.zh-CN.md` and `DotGrid/README.md` where they
   describe it, and add a `CHANGELOG.md` entry under an "Unreleased" heading
4. Bump `## Version` in `DotGrid.toc` only when preparing a release; the changelog entry and the tag
   (`vX.Y.Z`) should match it
5. Screenshots and recordings are welcome — drop them in `docs/images/` (see the note there)

## Reporting bugs

Include the output of `/dg diag` and the state header printed by `/dg help`. Both are designed to
answer "is it the range criteria, the containers, or the window this time" without a screenshot.

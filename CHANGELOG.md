# Changelog

All notable changes to DotGrid are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/) with a `0.x` major while the addon is still young.

## [0.9.17] — 2026-09

### Added

- **Localization layer**: all UI and chat text goes through a language table keyed by the Chinese
  original (`L["…"]`), with `Locales/enUS.lua` (472 entries) providing full English UI text.
  Adding a language is a new file plus one line in `DotGrid.toc` — no code change.
- `LICENSE` (MIT) and `## X-License: MIT` in the toc.
- Test suite guardrails: no user-visible literal may bypass the language table; the English table must
  cover every key and contain no Chinese in its values; an end-to-end run with `GetLocale()`
  forced to `enUS` must produce Chinese-free output.

### Changed

- In-folder documentation renamed to `README.md` and reorganised into the sections a published addon
  is expected to have; the project gained an English `README.md` (this file is the Chinese one).

## [0.9.16] — 2026-09

### Changed

- Documentation rewritten against the conventions of well-known addons: the README is now a product
  document (features / installation / quick start / command tables / FAQ / localisation / licence),
  and `/dg help` is a grouped, column-aligned list.
- Both main files open with a header comment stating their job and the constraints that must not be
  broken; section dividers and comment style unified.
- Addon metadata: neutral `## IconTexture`, shortened `## Title`, English `## Notes` with
  `## Notes-zhCN`, `## Notes-enUS`.

### Fixed

- The **Profiles page had no sidebar button**: the page was built (and counted) but could not be
  clicked. It is now the eighth tab. Found by the new test suite's page-count check.
- The "Clear spells (idle)" button still showed the old hint text of the button it replaced.

## [0.9.15] — 2026-09

### Changed

- Every user-facing string and comment reviewed: version history, development war stories and
  references to the test harness were replaced with plain statements of current behaviour.
- Test suite gained a text scan (no release versions, live-client anecdotes or developer phrasing in
  shipped files) and an absolute-path scan, both with self-checks.

### Fixed

- Two structural checks in the test suite had been appended to a list that was re-initialised later,
  so they never ran.

## [0.9.14] — 2026-09

### Changed

- No absolute paths anywhere in the addon; the test suite takes the addon directory from
  `DOTGRID_ADDON_DIR` (or a sibling `DotGrid/` folder).
- Documentation states explicitly that the addon writes no files and only reads client built-ins.

## [0.9.13] — 2026-09

### Changed

- **Idle by default**: with no watched debuff the addon scans nothing, computes nothing and draws
  nothing. Factory configuration no longer contains any spell IDs.
- The four built-in class profiles (rogue / warlock / priest / druid) were removed: new users and new
  characters start from an empty profile.

### Added

- `/dg spell clear` and the matching "Clear spells (idle)" button.

### Fixed

- Upgraded characters keep their settings: the character present at upgrade time adopts the migrated
  legacy profile instead of silently falling back to an empty one.

## [0.9.12] — 2026-09

### Added

- **Profiles** (option B): profiles live in the account-level save (`DotGridDB.profiles`) and each
  character points at one (`DotGridDB.charProfile`). Reads are "current profile ∪ factory defaults",
  writes go to the current profile. `/dg profile new|load|save|delete`, plus a Profiles page in the
  settings window with a name box and a list.

### Fixed

- Creating a profile no longer marks the character as "explicitly assigned", which used to stop the
  automatic per-class profile from ever being created.

## [0.9.10] — 2026-09

### Fixed

- The look frame is now hidden as well when the display goes away (out of combat, `/dg off`, mode
  switch) — it used to be left behind as an empty box.
- The outer frame no longer shows square corners: the backdrop needs a non-zero inset.

### Changed

- The settings window is drawn entirely by the addon again (no client textures).

## [0.9.0] — 2026-08

### Removed

- Pie mode (and its generated sector textures), the fixed-length bar mode, and the numeric count
  labels. Older save keys are migrated away.

### Added

- Three look modes (`solid` / `panel` / `nameplate`), per-key alpha handling, and the live preview
  canvas in the settings window.

## Early development (0.7.0 – 0.9.0)

Prototype phase: grid and pie renderings of "how many mobs carry my DoT", per-mob segments, a
self-drawn settings panel, drag-to-position, and the first range criteria (`CheckInteractDistance`
tiers plus optional exact yards). The features that survived this period are the ones described in
the README; the pie mode and the fixed-length bar did not, and were removed in 0.9.0.

[0.9.17]: https://github.com/blacklc/DotGrid/releases/tag/v0.9.17
[0.9.16]: https://github.com/blacklc/DotGrid/releases/tag/v0.9.16
[0.9.15]: https://github.com/blacklc/DotGrid/releases/tag/v0.9.15
[0.9.14]: https://github.com/blacklc/DotGrid/releases/tag/v0.9.14
[0.9.13]: https://github.com/blacklc/DotGrid/releases/tag/v0.9.13
[0.9.12]: https://github.com/blacklc/DotGrid/releases/tag/v0.9.12
[0.9.10]: https://github.com/blacklc/DotGrid/releases/tag/v0.9.10
[0.9.0]: https://github.com/blacklc/DotGrid/releases/tag/v0.9.0

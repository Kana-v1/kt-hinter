# Kill Team live tracker

A phone-first **native iOS app** for Warhammer 40,000: Kill Team (2024). It answers one question
mid-game: **"what can I use right now?"** It shows:
- the ploys, equipment, chapter tactics and abilities you can use now, with their price
- what's in play for the operative who's acting
- the rules those effects add to its weapons
- the acting operative's datacard

Teams: Angels of Death, Plague Marines, Celestian Insidiants and Spectre Squad. The user is a casual player: fewer taps beat rules precision.

## Scope: read this before adding features

This is a **bookkeeper, not a rules arbiter**. It tracks state and surfaces reminders; it never
resolves the game. This is the most important design decision. It came from prior art: Gloomhaven
Helper explicitly refuses to apply damage or validate legality, and two decades of open-source
Magic engines show what the alternative costs.

The app must never model:

- the board: positions, distances, line of sight, cover, control range
- dice resolution, damage, or wound totals
- anything requiring input the player won't give mid-game

**Rule text states conditions; it never asserts them.** The app can't see the killzone. So write
"Balanced if the target is more than 6\" away", not "you have Balanced".
- The exception is a condition the app genuinely knows because the player told it. Three exist today:
  - **who is acting** (the selected operative: `selectedIs`, `appliesTo`)
  - **who is incapacitated**
  - **an operative's status** the player set (INSPIRING, Benedictions: `statuses`, `requiresStatus`)
- Weapon-row notes (`+Poison +Severe · Plague Rounds`) are annotations. Stats are never rewritten.

## Layout

| Path | Role |
| --- | --- |
| `ios/KTEngine/` | Rules engine: a Foundation-only Swift package, Swift 5 mode. Builds and tests on Linux. |
| `ios/KTEngine/Sources/KTEngine/Rules.swift` | Codable census model. |
| `ios/KTEngine/Sources/KTEngine/Engine.swift` | `Event`, `GameState`, `fold`/`apply`, `routes`/`quote` (prices). |
| `ios/KTEngine/Sources/KTEngine/Derive.swift` | `derive` → `Snapshot`: grouped Use now / Active, elsewhere, weapon notes, `ruleInfo`. |
| `ios/KTEngine/Sources/KTEngine/Glossary.swift` | Splits rule text into tappable term segments. |
| `ios/KTEngine/Sources/KTEngine/GameLog.swift` | The persisted game: team plus event log. |
| `ios/KTEngine/Sources/KTEngine/Feedback.swift` | `FeedbackReport` (a problem report from the phone) and `describe` (a snapshot as text). |
| `ios/KTEngine/Sources/kt-feedback/` | `swift run kt-feedback`: prints and replays the reports in `feedback/`. |
| `ios/KTEngine/Tests/` | Scenario, applicability, data-integrity and glossary tests; `Golden/` holds the applicability tables. |
| `ios/KillTeam/` | SwiftUI app. `GameStore` owns the game; views follow the design canvas. |
| `feedback/` | Inbox for the phone's problem reports. Git-ignored except its README. |
| `ios/project.yml` | XcodeGen spec. Bundles `data/teams` and `data/core` straight from the repo. |
| `.github/workflows/ios.yml` | CI: engine tests, then an unsigned `.ipa`. **CI is the only iOS compiler.** |
| `data/teams/<id>.json` | Rules census per team: the single source of truth. |
| `data/core/glossary.json` | Core weapon-rule definitions, transcribed from the official Lite rules page. |
| `tools/rules-pipeline/` | Sync, extract, audit (`sync_sources.py`, `update-rules.sh`, `columns.py`, `audit.py`). |
| `tools/app_icon.py` | Draws the app icon. |
| `tools/add_ios_model_fields.py` | The reviewed table of `when`, `appliesTo`, `hint` and grants per rule. Re-run after census edits. |

Design canvas (screens, look): https://claude.ai/artifact/3vAvcCWU9RVELrduYHkHWA

## Architecture

```
GameLog.events   append-only: PHASE, CP, TP_NEXT(ini), ACTIVATE, END, OP, DOWN, LEADER, ROSTER, COUNT, EQUIP, TACTIC, STATUS, …
  ↓ fold()       Engine.apply → GameState { tp, cp, phase, roster, op, dead, equip, tactics, active, used, paid, … }
  ↓ derive()     + rules → Snapshot { use[when], active[when] for the acting operative, elsewhere, weaponNotes, summary }
  → SwiftUI      renders the Snapshot; every tap is one Event (GameStore.send), saved to Documents/game.json
```

Invariants, in order of importance:

1. **Derive, never mutate.** There's no "+1 on apply, −1 on expiry" anywhere. Expiry isn't an event:
   - `end_of_turning_point` effects drop when TP advances.
   - `this_activation` effects drop when a *different* operative is selected, because that's a new activation.
   - A team resource (Fieldcraft points) follows the roster during the Strategy phase, is fixed when
     the Firefight starts, and starts over at `TP_NEXT`.

   Subtract-on-expiry logic is the classic buff-system bug.
2. **The log is the state.** Every change is an Event, and state is `fold(events)`. Undo drops the last
   event. `GameState` is only changed in `Engine.apply`.
3. **The engine has no UI and no I/O.** Keep it Foundation-only so `swift test` runs on Linux.
4. **Persistence is best-effort.** A missing or corrupt save starts a fresh game; never crash over a file.

### Core rules the engine encodes (official Lite rules)

- **CP:** 2 at the start, +1 in the first Strategy phase, so 3 in turning point 1. After that the
  player with initiative gains +1 and the other +2. `TP_NEXT` carries `ini: us|them`, and the app asks.
- **Ploys** cost 1CP. Each ploy except Command Re-roll is once per turning point.
- **Phases:** strategy ploys are usable in Strategy; firefight ploys and activatable equipment in Firefight.
- A battle is four turning points.

## Data model

Every entry in `effects[]`:

| Field | Meaning |
| --- | --- |
| `kind` | `strategy_ploy` · `firefight_ploy` · `equipment` · `faction_rule` · `operative_ability` |
| `cost.cp` / `once_per` | Price and limit (`turning_point` / `battle`). `cost.resource` prices it in the team's resource instead. |
| `duration` | `instant` `this_sequence` `this_activation` `this_counteraction` `end_of_turning_point` `battle` |
| `when` | `activation` · `attack` · `defence` · `any`: which group it shows in. |
| `appliesTo` | `team` · `self` (only its `requiresOperative`) · `weapons` (with `weaponMatch[]`). |
| `hint` | One short, action-first line, shown on the card. `text` is the full rule. |
| `grantsWeaponRules[]` | `{match, rules, condition?}`: the weapon-row notes. `match` is `*`, `ranged`, `melee` or name substrings. |
| `trigger` | A moment the app sees that should offer the ploy (`incapacitated` → Poisonous Demise). |
| `options[]` | Sub-choices (Combat Doctrine), each with a `hint` and optional grants. |
| `requiresOperative` | Exists only while that operative is on the roster and not incapacitated. |
| `requiresStatus` | Applies only while its operative has that status (Inspired Strikes: INSPIRING). |
| `notFor` | Operative types a team-wide rule skips ("excluding VOX-RELAY BEACON"). |
| `alwaysOn` | Passive: always in play, never "use now". |
| `costOverrides[]` | Discounts it grants to other effects (see below). |
| `source` / `verify[]` / `disputed` | Provenance. `disputed` shows a red **Unverified** tag. |

Census `meta` also carries `rulesVersion` (e.g. "August '26"); the app shows only this, not the PDF name.
`meta.rosterSize` is the legal roster size (default 6; Celestian Insidiants 9), and an operative's
`max` caps its copies (Cremators: 2).

`statuses[]` (`{id, name, hint, grantsWeaponRules?, notFor?}`) are operative states the player sets
and clears with a `STATUS` event; the app can't see them happen. While set, a status shows on its
operative like a rule in play, with its weapon notes. This was added for Celestian Insidiants
(INSPIRING, Ardour, Wrath) — a real vocabulary addition, not a one-off.

`meta.resource` (`{id, name, short, gain, bonus?: {operative, gain, condition}}`) is a team currency
besides CP, added for Spectre Squad's Fieldcraft points. It's gained in each Strategy phase, plus the
bonus while that operative is on the roster and up, and discarded at the end of the turning point.
The player nudges it with `RES` events (±1), like CP. Effects priced with `cost.resource` are usable
in the Firefight phase and spend it; their cards and the recap show its `short` name ("1 FP").

### Cost overrides

- `effect` or `kind`: what it discounts.
- `options[]`: only certain sub-choices (Doctrine Warfare's doctrines).
- `excludes[]`: explicit exemptions (Heroic Leader doesn't discount Command Re-roll).
- `once_per` + `group`: a shared group means one use consumes every option of that ability (Heroic Leader).
- `selectedIs`: only when the acting operative is that one. Otherwise it shows as a dim "can be free" hint.
- `requiresStatus`: only while the operative granting it has that status (Holy Example, Accusing
  Exorcist need INSPIRING). Otherwise it's a "can be free" hint too.
- `condition`: human-readable text for what the app can't check.
- `cp` or `resource`: the new price, in the discounted effect's currency (Cool-Headed: `resource: 0`).

Vocabularies are closed (`vocab` in each census). If a card genuinely needs a new value, add it and say so.

## Sourcing rules: non-negotiable

**The newest official PDF, as linked on the downloads page, is the authority** (errata included).
Secondary sites (ktdash, ktdojo, wahapedia) are hints only; they have been wrong. A web-searched
January PDF once nearly deleted real weapons that the August update had added.

Get rules **only** through the pipeline:
`update-rules.sh --sync --all`, then `audit.py <team>`, then a visual pass on the rendered pages, then
a reviewed edit of the census, then `tools/add_ios_model_fields.py`.
- **Never web-search for a PDF link or hand-edit one.** `sync_sources.py` reads the downloads page's
  own API (POST `https://www.warhammer-community.com/api/search/downloads/` with
  `{"index":"downloads_v2","searchTerm":"","gameSystem":"kill-team","language":"english"}`)
  and rewrites `sources.json`. `sync_sources.py --check` exits 1 if GW published something newer.
- **Never `WebFetch` a PDF.** It returns a model's summary, which has invented rules.
- `lit` (liteparse 2.x) does the extraction. Under WSL the Windows `lit` rejects UNC paths, so
  `update-rules.sh` stages PDFs in a Windows temp dir. Outputs (`data/pdf/`, `data/extracted/`) are
  git-ignored: GW's PDFs never go in this public repo.
- **Text extraction can't see strikethrough,** so deleted errata text reads as live. Check errata
  boxes on the page images.
- Glossary definitions come from the official Lite rules page, read visually, never from memory.
  Ceaseless ≠ Relentless.

AoD and Plague Marines were checked page by page against the August '26 PDFs on 2026-09-26,
Celestian Insidiants on 2026-09-27, Spectre Squad on 2026-10-04. Nothing is unresolved.

## Team notes

- **Angels of Death:** 1 leader (Captain, Intercessor Sergeant or Assault Intercessor Sergeant) plus 5.
  Warriors repeat (`intercessor_warrior#2`; `typeOf()` strips the suffix). The leader changes the rules:
  - the Captain brings Heroic Leader (a firefight ploy free for the Captain, once per TP) and Iron Halo
  - the Sergeants bring Doctrine Warfare (two doctrines free once per battle each) and Chapter Veteran
    (an extra chapter tactic, for that Sergeant only)
- **Plague Marines:**
  - Champion plus 5, each operative once. There are no chapter tactics.
  - Poison is tracked by the player, not the app: rules about it are reminders.
- **Celestian Insidiants:**
  - Superior plus 8. Warriors repeat, Cremators up to two, the rest once. No chapter tactics.
  - INSPIRING and the lasting Benedictions (Ardour, Wrath) are statuses the player taps on the
    operative sheet. Restoration and Exigence are one-off, so they're text only.
  - The Superior has two loadouts; its datacard lists every weapon from both.
- **Spectre Squad:**
  - Veteran Sergeant, Vox-Relay Beacon, plus 9. Troopers repeat, the rest once. No chapter tactics.
  - Fieldcraft points: 2 per turning point while the Vox-Operator is up, else 1. The Vox-Operator's
    enemy control range can't be seen, so the player taps − if it doesn't count.
  - Elite Fieldcraft is a "Use now" card for 1 FP. Cool-Headed makes it free once per turning point
    while a Trooper is acting.
  - The Beacon (no weapons) skips the team-wide rules it can't use: Expendable allows only Signal.
  - The roster page gives the Gunner fists; its datacard (followed) has a gun butt.

## UI conventions

- Apple HIG, committed dark theme (gaming tables are dim). System font with rounded numerals, grouped
  inset lists, sheets.
- Colours have fixed meanings, always paired with text or an icon:
  - green = usable
  - orange = in play
  - red = locked or unverified
  - blue = interactive or a rule term
- Two phases (Strategy / Firefight), not seven moments. Logging cost beats precision for this user.
- Rule names open their full text, and terms inside text open their definition. The blocks fold.
- Chips **wrap**, never scroll sideways (`FlowLayout`).
- One tap for the common path.
- Operative photos and team symbols are the player's own, on the phone only, never bundled or
  committed. Files are matched by name: `…_<operative id>` or `…_<team id>` (longest id wins).
- The app icon is an original design, drawn by `tools/app_icon.py`. No GW artwork in the repo.

## Feedback reports

The speech-bubble button (game screen, operative sheet, Setup, every rule sheet) saves a
report on the phone: the player's note plus the app's state. That state is the whole
`GameLog` (it replays exactly), `shown` (`Engine.describe` of the snapshot on screen), `screen`
(where they were, with the rule id on rule sheets), view state, the build's commit, a log tail
and an optional screenshot.

- **Reading them:** when the user says they sent feedback, run `cd ios/KTEngine && swift run kt-feedback`.
  - It writes each screenshot beside its report as a `.jpg`; look at it with Read.
  - Its replay diff on today's census and code shows whether a fix changed what the player saw.
  - Reproduce from `game.events`, not from the note.
- **Fixing:** where it fits, turn a report's events into a regression test.
- **Never lose one:**
  - The phone keeps every report until the player deletes it. Sending only moves it to `feedback/sent/`.
  - In the repo, move handled reports to `feedback/done/`; don't delete them.
  - Never commit them: screenshots can show the player's own operative photos.
- `describe` must keep covering what the screens show. Add a field there when a view gains one.

## Verification

- Run `cd ios/KTEngine && swift test` for anything touching the engine or census. Swift is at `~/sdk/swift`.
- The applicability tables in `Tests/KTEngineTests/Golden/` fail on any change to who-sees-what.
  Review the diff, then regenerate with `KT_UPDATE_GOLDEN=1 swift test`.
- iOS UI code compiles only on CI. Push, then `gh run view <id> --log-failed`. Keep to iOS 17 APIs,
  Swift 5 mode, and avoid names that clash with SwiftUI (`View`, `State`, `Group`, `GroupBox`).
- GitHub auth: the token is `GITHUB_PERSONAL_ACCESS_TOKEN` in `~/.bashrc`, which isn't loaded in
  non-interactive shells. Read it into `GH_TOKEN` per command, and never print it.

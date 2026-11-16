# JCDR fork review

Reviewed 2026-11-16 against HaploBox commit `a88bcc3` and the current local
working tree (including the pre-existing uncommitted death controls).
No addon code was changed or merged during this review.

Source: [JCDRTV/HaploBox-JCDR-Edition, jcdr-development](https://github.com/JCDRTV/HaploBox-JCDR-Edition/tree/e48cb5859fe4868dd38227eafeb213f0203dca06).
The fork's `main` matches our baseline. Development is at `e48cb58`, with
two additional commits changing 67 files (+8,056 / -1,543 lines). It is a
development snapshot with an older Core implementation and an Alpha4 subsystem,
rather than a small patch on our current behaviour.

## What the fork adds

These are implemented code paths, not claims of in-game correctness or Blizzard
approval. Overlapping features are distinguished from new capabilities.

| Capability | Difference from our current version | Relevant code / qualification |
| --- | --- | --- |
| Smart Follow | One generated macro: direct follows the leader; dungeon follows the healer, with the healer following the leader | BoxMode.lua:186-237. Healer selection uses Blizzard roles; leader selection assumes party1. Missing/multiple follower-side healers make it inert. |
| Managed spell macros | Explicitly create macros with ordinary casting while BOX is off and assist/heal targeting while on; import one plain /assist focus line | BoxMode.lua:78-181. No automatic scanning of arbitrary user macros. Targets party1, not a resolved leader. |
| Shared BOX toggle | Leader sends ON/OFF, followers acknowledge, changes defer during combat; local OFF available | BoxMode.lua:256-340. New build notes explicitly say not live tested on five clients. |
| Party combat indicator | Replaces the visible focus tile with reported combat state; stale state becomes unknown | BoxMode.lua:342 onward; Party.lua updateCombat. Focus infrastructure remains in code. |
| Blizzard party-leader awareness | Reads the actual party leader; click a follow tile to request promotion | Core.lua GroupLeader/Leader; Gameplay.lua PromoteName; Party.lua box OnClick. Different semantics from our independent stored HaploBox leader. Does not connect window switching to leadership. |
| Mixed-party auto loot | FFA for recognized team members; group loot when an outsider is present | Gameplay.lua CheckAutoLoot. Highly relevant to #7, but manual loot paths and trust matching need fixes. |
| Party controls | Invite missing team members, local leave, shared quest/trade toggles and assign-self-healer action | Gameplay.lua and ControlBar.lua. Includes personal defaults and hardcoded invite-name mappings. |
| Grouped quick settings | Gear opens a themed flyout with BOX, follow, roles, party controls, and buff/debuff sections | ControlBar.lua. Relevant to #6/#9; not a unified replacement for all settings. |
| Separate settings window | /hb4 options opens a standalone window for frame display, repair, whispers and UI sharing | Alpha4/Options.lua. Original /hb options still exists, so configuration is split. |
| Mini Heal view | Five large secure target/mouseover health tiles for small follower windows; local main/heal toggle | MiniHeal.lua. Changes an entire local frame layout; does not cast heals automatically. |
| Incoming heal display | Prediction overlays on main and Mini Heal health bars | HealPrediction.lua. Needs actual-client validation of native status-bar geometry and protected values. |
| Expanded aura display | HoT rail, missing-required-buff tracking, separate draggable buff/debuff overviews with timers and player badges | Auras.lua. Existing HaploBox already shows long-duration team buffs; these are substantial extensions. Includes native AuraContainer path with legacy fallback, not validated here in game. |
| Cast and mana-use tracks | Slim cast/channel progress plus a five-second mana-regeneration-rule indicator | Party.lua:969 onward. Observed events and addon telemetry; not evidence that a keypress succeeded. |
| Share UI to party | Transfers selected settings, dimensions and normalized positions; chunking, checksum, acknowledgement/retry, combat deferral | Alpha4/Sync.lua. Excludes local main/heal mode and keybindings; separate HB4EX protocol. |
| Top status bar and minimap skin | Full-width HaploBar; square native minimap; relocated native tracking/mail/calendar/clock controls | HaploBar.lua. This is presentation, not follower-discovered gathering-node sharing. |
| Inventory helpers | Shared per-item junk marking/unmarking and bag overlays; personal-funds auto repair | Alpha4/Inventory.lua. Auto-selling is deliberately locked off because unmark synchronization is unresolved. |
| Trade material routing | Optional autofill by explicit item rules or profession matching; does not accept a trade | Trade.lua. Experimental; new inventory-moving behaviour needing separate review. |
| Resource presentation | Compact per-toon gold/bags, coloured capacity display, team totals, cached samples | Party.lua, ControlBar.lua, Alpha4/Information.lua. XP/rested, money, bags and totals already exist in our version; most of this is redesign, not new capability. |
| Kills-to-level estimate | XP-gain estimate and settings exist | Alpha4/Information.lua. Current display is suppressed with local show=false and an if-false totals branch; not a working visible addition as shipped. |
| Private incoming whispers | Separate optional private forwarding implementation | Alpha4/Whispers.lua. We already have a more complete implementation with replies, long-message splitting and delivery/error handling; the fork truncates text and has no reply relay. |

## Findings relevant to integration

1. **Leader is not necessarily party1.** Both generated spell assist and direct
   follow use party1. The fork's own notes describe that as a JCDR team convention.
   That convention does not meet our any-team/window-independent requirement.
   A mocked check with Mael at party3 still generated /follow party1.
2. **Smart Follow and follow indicators have different healer sources.**
   BoxMode.lua reads UnitGroupRolesAssigned, while Core.lua Healer reads stored
   HaploBoxTeam.roles and ExpectedFollowTarget uses that stored healer.
   Picking the Blizzard role alone does not establish that indicators agree.
3. **Combat changes retain the old prepared macros.** They cannot deliver an
   immediate combat-time leader change. Spell macro bodies lack a group
   conditional, so a party change during combat can retain old party1 targeting
   until the deferred update. This is more than simply switching BOX off solo.
4. **Follow ownership does not preserve later user edits.** Spell macros compare
   their current body with the last applied body. Smart Follow only checks an
   ownership flag. A mocked user edit to HB Smart Follow was overwritten on the
   next PrepareSmartFollow call.
5. **Trust is inconsistent and partly personal.** Gameplay trusts configurable
   short names; BOX has another similar check; Alpha4 additionally trusts five
   hardcoded full names. Core follows actual party leadership and no longer uses
   our accepted-team offer mechanism. Do not import those definitions wholesale.
6. **Loot protection is incomplete.** CheckAutoLoot is a useful starting point,
   but the quick-menu LOOT button can select FFA and turn auto protection off
   without checking outsiders. Its client-API compatibility and authority checks
   also need to match our supported builds.
7. **The Core protocols conflict.** The fork uses D for follow mode, Y for
   cast/mana pulses, and P for professions. Our Core uses those for team death
   commands, private replies and flights respectively. Selective features need
   deliberate protocol allocation, not file copying.
8. **Newer functionality would be lost or weakened by replacement.** Our
   accepted-team validation, queued/throttle-aware messaging, private reply relay,
   role validation, tracker handling, automatic role application and flight
   coordination are absent or materially different. Fork quest acceptance no
   longer checks that the quest giver is a team member. Its primary Core handler
   no longer has our centralized per-message sender/channel policy.
9. **No complete custom keybinding menu yet.** Bindings.xml exposes Mini Heal and
   junk marking, while Smart Follow's helper explicitly offers F1. It does not
   provide the configurable role-action menu or window-switch integration we
   discussed.
10. **The settings are still fragmented.** The grouped quick menu is useful UI
    work, but options remain distributed across /hb options, /hb4 options, the
    quick menu and slash commands. Treat it as design input for #6/#9.

## Verification performed

- Current working tree: Lua 5.1 syntax and bindings passed; **47/47 behaviour
  tests passed**, including the existing local death-control work.
- Fork: all 20 TOC-loaded Lua files and its two bindings passed the existing
  syntax/binding checks.
- Fork's dedicated BOX smoke script passed (its output reports 23 assertions).
- Two additional mocked scenarios confirmed the party1 assumption and follow
  macro overwrite described above. No game action was performed.
- The inherited full fork suite reported **0/41 passing**. Most tests stop at
  ControlBar.lua:676 because the old frame mock supplies no numeric frame width;
  two also reference the removed SplitText helper. This demonstrates that the
  inherited suite has not been maintained for this branch. It does **not**
  demonstrate 41 real-client defects.
- No live-client UI, taint, casting, follow, loot, or multi-client checks were
  performed. The BOX development notes also explicitly call for those checks.

## Recommended reuse

**First:** adapt the role-discovery and explicit managed-macro ideas (#4/#8),
the mixed-party loot decision (#7), and the grouped quick-menu layout (#6/#9).
Resolve the findings above before implementation.

**Separate optional additions:** Mini Heal, incoming-heal overlays, cast/5SR
tracks, expanded buff/debuff views and Share UI. They add useful functionality,
but are independent changes and should not arrive implicitly with a macro fix.

**Leave out of this integration:** hardcoded team identities, wholesale Core or
Alpha4 replacement, experimental trade autofill, locked auto-selling, dormant
KTL controls and the minimap redesign unless specifically selected. Preserve our
existing XP/resource/whisper features rather than installing parallel systems.

**Still missing:** seamless compliant switch-and-lead, proven immediate combat
handover, role macros without party1 assumptions, a unified options system,
complete outsider guards, and follower-discovered gathering nodes (#5).

## Pre-mortem retained for any later implementation

- **PM-1 — High — trust/privacy/protocol regression.** Evidence: Core comparison
  and overlapping D/Y/P meanings. A wholesale merge loses established security
  and messaging behaviour. Guardrail: selective adaptation, preserve accepted
  roster and private routing, verify current protocol tests. Current disposition:
  **Prevented for this review** because no code was merged; implementation still
  requires those guards.
- **PM-2 — High — wrong leader/healer.** Evidence: BoxMode buildSpell/followBody,
  Core Healer/ExpectedFollowTarget and the party3 reproduction. Guardrail: one
  consistent role resolver, explicit leader semantics and tests with reordered
  parties and changed Blizzard roles. Disposition: **Unresolved for integration**.
- **PM-3 — High — stale or overwritten macros.** Evidence: combat deferral and the
  ownership reproduction. Guardrail: preserve external edits, safe solo/party
  transitions, visible pending state and explicit combat limitations.
  Disposition: **Unresolved for integration**.

Verdict: **REVISE PLAN** before importing these features. The useful ideas remain
viable subjects for exploration, but the fork's party-order and trust assumptions
do not meet our requirements. This review does not certify policy compliance;
issue #3 remains the place to record official policy/API evidence.

## Update: JCDR branches of 2026-11-16 (TB19.1m and TB19.1n)

Reviewed 2026-11-17 against these branches of the `jcdr` remote:

- `jcdr-total-overhaul-macros-mvp` (`ecec813`, 21 commits after `e48cb58`)
- `jcdr-total-overhaul-tb19-1n-preview` (`638c1f1`, the same plus one)
- `jcdr-spell-database-prep` (`9a119ba`, docs and inactive data only)

The fork's own notes say none of this has been tested in the game. Nothing was
merged.

### What the branches add

- **Macro Menu (`/hb macros`):** creates HaploBox-owned Blizzard macros for
  Smart Follow, Assist, Trade with leader and Druid spell presets, which the
  player places on bars by hand. Bindings are offered with an explicit
  collision confirmation.
- **BOX ON/OFF spell macros:** BOX OFF casts normally. BOX ON assists `party1`
  for damage spells, and heals with Shift on yourself, then a friendly
  mouseover, then `party1`. The leader has its own profile without assist.
- **Smart Follow:** direct mode follows `party1`. Dungeon mode makes the
  healer follow `party1` and the others follow the one Blizzard healer; with
  no healer or more than one, the macro does nothing.
- **Sync Team:** the leader can push macro and binding setup to followers that
  opted in, with answers in chat.
- **Spell data prep:** Druid spell inventories and targeting profiles,
  documented but not loaded.

### Taken into our designs

Recorded in [design-notes.md](design-notes.md) under #4 and #8:

- Healer resolution that refuses to guess: none or several healers means the
  follow control does nothing, and says why.
- The heal conditional `[mod:shift,@player][@mouseover,help,nodead][@<fallback>,help,nodead]`
  as a candidate, with a resolved fallback.
- Exact-body macro ownership: a HaploBox macro is rewritten only while it still
  matches what HaploBox wrote; personal edits are never overwritten.
- Safe states: off at login until the group is confirmed, off solo, in raids
  and in non-team groups; protected changes only out of combat.

### Not taken

- **`party1` as the leader.** It is the first other member in each client's own
  list. It is often the leader, but not after members leave or the leader
  changes. Our controls resolve the leader by name, out of combat.
- **`/assist party1` then `/cast`.** If assisting fails, the cast can go to an
  old, unrelated enemy (see #8).
- **Binding sync.** Layout sharing (#14) leaves key bindings out on purpose.
- **A wholesale merge.** The branches build on an older Core and a separate
  HaploBar/Quick Menu structure; ideas are taken one at a time.

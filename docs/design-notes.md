# Design notes: open exploration issues

These notes cover issues #2, #4, #5 and #8. They are designs, not features: nothing
here is implemented. Every one of them needs checks in the real client before any
code is written. The policy rules in [compliance.md](compliance.md) apply to all of
them: no input broadcasting, no gameplay started by a message from another toon,
and no way around a client restriction.

Statements marked **verify** are assumptions from source code or other people's
reports. Nobody has tested them in the game.

## #2: Team frame rows driven by SecureGroupHeaderTemplate

### Problem

Rows are `SecureUnitButtonTemplate` buttons bound to unit tokens (`party1` and so
on). Addons cannot rebind them in combat. When the group changes in combat the
tokens move, and a row can click-target a different character than its label
shows. HaploBox dims such a row and shows `?` until combat ends, but the click
still goes to the wrong unit.

### Design

- **Secure rows:** let a `SecureGroupHeaderTemplate` header create and bind the
  rows. The game rebinds header children in combat. The intended invariant is
  that a row's unit and its label never disagree. To get that, the label is drawn
  from the row's own `unit` attribute in `OnAttributeChanged`, never from
  HaploBox's team list.
  - **verify:** that the invariant holds in combat on every target client.
  - Evidence so far:
    [SecureGroupHeaders.lua](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_RestrictedAddOnEnvironment/SecureGroupHeaders.lua)
    in the generated retail UI source has `NAMELIST` sorting and in-combat
    rebinding. This covers current retail source only, not Forever or Classic Era
    and not live behaviour.
- **Order:** set `sortMethod = "NAMELIST"` and `nameList` to the team order
  (leader, tank, healer, then DPS). Set both out of combat whenever the team
  changes. Group members outside the team are left out by the name list.
  - **verify:** what the header does with a name that matches nobody, and with
    names that carry a realm.
- **Show the player:** `showPlayer = true`, `showParty = true`, and
  `showRaid = false` while the team setup is party-only.
- **AWAY rows:** team members who are not in the group get ordinary, non-secure
  placeholder rows under the header. These cannot be clicked to target, which is
  correct because there is no unit to target.
- **Sizes and Mini Heal:** the header lays children out with `point`,
  `xOffset` and `yOffset`. Row size changes happen out of combat through
  `initialConfigFunction` or by resizing the existing children. The existing
  combat deferral (`pendingLayout`) stays for size and view changes.
- **Hooks:** the row hooks (`create`, `size`, `refresh`, `clear`) keep their
  contract. `create` runs from the header's `initialConfigFunction` and its Lua
  callback, out of combat.

### Risks and checks

- **verify:** that `SecureGroupHeaderTemplate` exists and behaves the same on
  Forever 16001, Classic Era 11508 and retail 120105.
- `initialConfigFunction` runs in a restricted environment. Anything that is not
  secure setup must happen in an insecure callback after the child exists.
- The header can create children in combat. Those children must work with no Lua
  setup until combat ends: give the template its look in XML, not in Lua.
- Test in game: someone joins and leaves in combat, a reload in combat, a group
  converted to raid, and someone going offline.

### Outcome

When this works, `markStaleRows` and the `?` state are no longer needed for the
secure rows. Until then the current mitigation stays, and #2 stays open.

## #4: Trusted leader handover and role-based follow and assist controls

### Policy line

Switching game windows belongs to the window tool (WoWWindowKit), not to the
addon. HaploBox does not forward or inject keys. In the game, a handover is one
explicit key press or click on the toon that becomes the leader.

### Handover protocol

- **Who:** only a member of the accepted team can take over. Use the existing
  binding "Make this toon the leader" (`HB.MakeMeLeader`), or a new `/hb lead`
  that does not rebuild the team.
- **Roster:** a new message (a free kind, not one used by the fork) carries
  `leader|rosterHash|epoch`.
  - Receivers accept it only when the sender is in their current roster and the
    hash matches their roster.
  - Roles and team order do not change. Only the leader name changes.
  - A different roster still goes through the existing acceptance popup.
- **Order of offers:** the epoch grows across reloads, as share ids do. A lower
  epoch is stale. When two offers have the same epoch, the lower normalized name
  wins, so every toon picks the same leader.
- **Not automatic:** a dead or disconnected leader is not replaced. The player
  hands over by hand. The HaploBox leader is separate from the Blizzard party
  leader, and the UI shows both.
- **Combat:** the leader name is addon state and can change in combat.
  Protected controls (follow and assist buttons, macros) update only when combat
  ends. Until then they show "pending" on the team frame.

### Role controls

- Add secure buttons such as `HaploBoxFollowLeader`, `HaploBoxAssistLeader` and
  `HaploBoxFollowHealer`.
  - Their attributes (for example `type = "macro"` with `/follow <name>`, or
    `type = "assist"` with `unit`) are set out of combat from one resolver.
  - User macros use `/click HaploBoxAssistLeader` and never contain character
    names.
- The healer resolver is shared by the follow indicators, the macros and the
  team frame:
  1. the team role, then
  2. the Blizzard role, then
  3. none.
  - With more than one healer, use the first in team order and say so in the
    settings.
- Never follow yourself. A healer that is the leader makes "Follow healer"
  follow the leader. A follower whose healer follows it falls back to the
  leader, so there is no follow loop.
- Key bindings live under Keybindings > AddOns > HaploBox, with no keys
  assigned. Existing bindings and the focus target are left alone.

### Open questions

- **verify:** whether F2/F3 key-down can stay with the window tool while the
  same key also works in game. This is a WoWWindowKit question. Without that,
  the documented flow is: switch with the window tool, then press the handover
  binding.
- Raids and teams of more than 5 wait for #2.

## #5: Gathering nodes found by followers, shown on the leader's minimap

### What the client allows

The [PartyGatherRadar](https://www.curseforge.com/wow/addons/partygatherradar)
author reports that Forever build 70862 gives a minimap icon's name only while the
real cursor is over it. This is the author's report, not Blizzard guidance.
- **verify** this on the installed build.
- HaploBox does not move the cursor, does not scan the minimap and does not read
  pixels or memory.

### Design under that limit

- **Sources:** two observations, both made by a player on the follower:
  - **hover:** the player moves the mouse over a minimap node, and the minimap
    tooltip names it. Position is taken from the cursor's offset from the minimap
    centre, the minimap zoom and rotation, and the player's map position.
    - **verify:** whether the zoom can be read, and how accurate the result is.
  - **gather:** the follower gathers a node, and the loot or spell event gives
    the node type and the player's position.
- **Report:** `type|mapID|x|y|source|time` by addon message, only to the
  current leader, only from accepted team members. Messages are rate limited.
- **Leader map:** the leader merges reports that are close together, stores at
  most a fixed number, and lets markers expire (for example after 10 minutes).
  - A marker says "seen by <toon> <n> min ago". It never says the node is there
    now.
  - A gather report removes the marker. A missing report proves nothing.
- **Instances:** no reports where the player position is hidden.
- **Settings:** share on/off on each follower (off stops sending at once), and
  show on/off, herbs and ore, and expiry on the leader.

### Fallback

If hover data is not available, the only option is a marker the player places by
hand. HaploBox will not ship a spawn database shown as live nodes.

## #8: Spell macros that assist the leader in a team and cast normally solo

### Mechanism

- A secure button, `HaploBoxAssist`, is the only thing HaploBox changes. It is
  set out of combat:
  - **in an accepted team, on a follower:** `type = "assist"` with the leader's
    unit token.
  - **otherwise** (solo, a random group, on the leader, or the leader not in the
    group): the button does nothing.
- **Candidate macro (unverified; not a recipe):**

      #showtooltip Frostbolt
      /click HaploBoxAssist
      /cast Frostbolt

  HaploBox would not edit this macro or need character names. Solo, the click
  would do nothing and Frostbolt would cast at the current target as normal.
  Do not recommend it until the targeting checks below pass.
- **Groups:** the button is active only when the group is the accepted team
  (`HB.GroupStatus()` is "team"). In a mixed group or a random group it stays off.
  Being in some group is never enough.
- **Combat:** the button is updated only out of combat. If the leader or the
  group changes in combat, it keeps its old setting until combat ends. The team
  frame shows "assist: pending".
  - The leader unit token can move in combat (#2). Until #2 is solved, the button
    is set to the leader's unit token and also checked by name when combat ends.
  - A pending notice does not make a stale binding safe. It only tells the player.

### Fail-closed targeting: required before any recommendation

When assisting fails, the cast must not go to an old, unrelated enemy. Nothing in
this design does that yet. A dead-target clear would not help, because the old
enemy can be alive.
- **verify:** what `/assist` does when the leader has no target, or the target is
  friendly, dead or out of range. Does it keep the follower's current target or
  clear it?
- **verify:** the same during a combat roster change and a team-to-solo change
  in combat.
- If the old target can survive a failed assist, this mechanism is not safe as
  designed. A different secure design is needed, or a manual alternative.
- **Off switch:** an on/off setting on each toon (default off). The team frame
  shows the current state.
- Focus is not used.

### Not doing

- No `EditMacro` rewrites of user macros.
- No actions started by leader messages. A leader message changes only the
  leader name, which the button reads out of combat.
- No Frostbolt example in the README until it has been tried on Forever.

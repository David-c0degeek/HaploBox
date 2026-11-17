# Design notes: open exploration issues

These notes cover issues #2, #4, #5 and #8. The owner approved the designs on
2026-11-17, and #2, #4 and #8 may be built and tested offline. Checks in the real
client still gate any recommendation to use a feature and the closing of its
issue. The policy rules in [compliance.md](compliance.md) apply to all of
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
  team frame. It counts the Blizzard HEALER role among the accepted team members
  in the group, the player included, and needs exactly one.
  - None or two or more: "Follow healer" does nothing, and the settings say why.
    This follows the JCDR fork, which leaves its follow macro inert in the same
    cases rather than guessing.
  - Stored HaploBox roles are not read by the resolver. They matter only because
    HaploBox applies them as Blizzard roles (`HB.ApplyRoles`), so both always
    come from the same source.
- Never follow yourself. A healer that is the leader makes "Follow healer"
  follow the leader. A follower whose healer follows it falls back to the
  leader, so there is no follow loop.
- Key bindings live under Keybindings > AddOns > HaploBox, with no keys
  assigned. Existing bindings and the focus target are left alone.
- **Safe states (from the JCDR fork):** role controls are inert solo, in raids,
  and in a group that is not the accepted team. They become inert again at
  login until the group is confirmed. Attribute changes happen only out of
  combat; a change asked for in combat waits and is shown as pending.
- **Not from the fork:** it targets `party1` as the leader. `party1` is only the
  first other member in that client's list. It is often the leader when the
  leader formed the group, but not after members leave or the leader changes.
  These controls use the resolved leader name instead.

### Open questions

- **WoWWindowKit finding (read 2026-11-17, `c381c9e`):** `KeyboardHook.cs`
  `HandleKey` swallows a swap key's key-down and its key-up when a managed WoW
  window is in front (`return 1` from the low-level hook), so the game never
  sees F2/F3. Letting the key through would deliver it to the window being left,
  not the new one, and sending it to the new window would be key injection.
  So the flow stays two presses: switch with WoWWindowKit, then press the
  HaploBox take-over binding. Any WoWWindowKit change is a separate piece of
  work in that repository.
- **Built (offline, 2026-11-17):** `Lead.lua` has the handover and the three
  role controls as described above.
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

### Built (offline, 2026-11-17): `Cast.lua`

This replaces the `/assist` candidate below, which stays for the record.

- **Buttons:** `HaploBoxCast1` to `HaploBoxCast12` hold spells in fixed slots. The
  player's macro clicks one; HaploBox never edits macros.
- **Damage:** `/cast [@<leader token>target,harm,nodead] <spell>`. Without a living
  enemy target on the leader nothing is cast, and the player's target never
  changes, so a failed assist cannot hit an old, unrelated enemy.
- **Heals:** `[mod:shift,@player][@mouseover,help,nodead][@<leader name>,help,nodead]`.
  The leader is named, so a moving party token cannot redirect the heal.
- **Secure disarm in combat:** a party token can move in combat, so armed damage
  buttons are emptied by secure code on any group change:
  - a leader-only `SecureGroupHeaderTemplate` runs `refreshUnitChange` on every
    roster or name update (source: `SecureGroupHeaders.lua` `configureChildren`,
    live retail);
  - `_onattributechanged` runs when the leader's row loses its unit;
  - a state driver runs on any change away from a party.
  HaploBox arms the buttons again only out of combat, after checking the group.
- **Off switch:** off after every login, and off in solo, raid, mixed or
  unconfirmed groups and on the leader.
- **verify:** that the header, `refreshUnitChange`, `_onattributechanged` and the
  state driver behave like this on Forever and Classic Era. Also verify
  `@<token>target` and `@<name>` in macro conditionals, and that `/click` reaches
  a hidden secure button there.
- **Gap:** a leader change by handover in combat (#4) is not a group change, so it
  does not disarm. Armed damage then follows the old leader's target, which is
  another team member's, until combat ends.

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
- **Heal variant (from the JCDR fork):** for heals, a candidate conditional is
  `[mod:shift,@player][@mouseover,help,nodead][@<leader>,help,nodead]`: Shift
  heals yourself, then a living friendly unit under the mouse, then the
  fallback. Heals fail closed by nature (`help` refuses an enemy), so this
  variant carries less risk than assist. **verify** on Forever, and keep the
  fallback a resolved name or the button's unit, never `party1`.
- **Fork assist pattern rejected:** its DPS macros use `/assist party1` followed
  by `/cast`. That has the fail-open problem above, and `party1` is not always
  the leader.
- Focus is not used.

### Not doing

- No `EditMacro` rewrites of user macros. If HaploBox ever creates macros of its
  own (as the fork does), it rewrites one only while its text still matches
  exactly what HaploBox wrote, and never a macro the player has edited.
- No actions started by leader messages. A leader message changes only the
  leader name, which the button reads out of combat.
- No Frostbolt example in the README until it has been tried on Forever.

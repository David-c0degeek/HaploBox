# Blizzard policy and mixed-group review

Tracks issues #3 (policy review) and #7 (mixed groups). Reviewed 2026-11-16
against the code after the death-control and mixed-group loot changes.

This is an inventory and a record of decisions. It is not a claim that Blizzard
approved anything. The policy in question is Blizzard's May 2021 statement on
input broadcasting and multiboxing:
<https://us.forums.blizzard.com/en/wow/t/policy-update-for-input-broadcasting-may-2021/956613>.
It forbids software or hardware that mirrors input across accounts, and
mechanisms that automate or streamline multiboxing. Being possible through the
Lua API does not make something allowed.

## Ground rules for new work

- No input broadcasting, key forwarding or injected input, in HaploBox or in
  WoWWindowKit. A switch key that also sends a game or leader command is a
  separate proposal and is not approved by this review.
- No bypass of client restrictions: no simulated hover, minimap sweeps, memory
  or pixel reading, and no in-combat rewriting of protected actions.
- A new mechanism whose status under the policy is unclear stays unbuilt, or off,
  until the owner decides. Look for a manual alternative first.
- Being able to switch something off is not evidence that it is allowed.

## Client evidence

`HaploBox.toc` declares `## Interface: 16001, 11508, 120105` (WoW Forever,
Classic Era, retail). That is a load declaration, not verification.

- Offline: every Lua file compiles under Lua 5.1, and `tests/run.py` runs the
  behaviour tests against stubbed APIs. The stubs model what the code expects,
  not what a client does.
- In game: earlier releases were built against WoW Forever. Nothing in this
  review was checked live on any client, Classic Era and retail included.
- API use is feature-detected (`C_PartyInfo.SetLootMethod`, `SetLootMethod`,
  `GetLootMethod`, `UnitIsGhost`, taxi and quest-log APIs). A missing API means
  the feature does nothing and says so. Whether an API is protected says
  nothing about whether its use is allowed by policy.

## Owner decisions

- **Leader-triggered follower actions** (Release team, Rezz team, following the
  leader's flight): accepted by the owner on 2026-11-16 as established multibox
  addon behaviour ("multiple addons have had this for years"). They stay on by
  default. Each still needs a click by the leader, and each follower acts only
  on a message from its own stored leader. Blizzard has not ruled on these
  specifically; the owner's acceptance is the basis, not an official statement.
- **Abandoning a quest on the team**: requested by the owner on 2026-11-16, in the
  same category. It needs the leader's own abandon and a Yes in the popup; No does
  nothing on the followers.

## Feature inventory

"Client" is where the action happens. "Input" says whose click or key starts it.
Mixed group: what changes when someone outside the team is in the group.

| Feature | Trigger | Action, client | Input | Mixed group | Status |
| --- | --- | --- | --- | --- | --- |
| Accept invite | Party invite from the stored leader | `AcceptGroup` on the follower | Leader invites | Only the stored leader's invites | Common addon behaviour; kept |
| Share accepted quests | This toon accepts a quest (`QUEST_ACCEPTED`) | `QuestLogPushQuest` to the whole group | This toon accepts the quest | Shares go to everyone in the group, outsiders included (Blizzard's own share); outsiders' auto-accept is their choice | Leader only by default (`autoShareQuests`); kept |
| Accept shared quest | A team member shares a quest | `AcceptQuest` on the follower | Team member shares | Shares from outsiders are not accepted | Kept |
| Role check answer | Game role check | Answer with the stored team role | Group finder | Not affected | Kept |
| Party role icon | Team change, roster change | Set own role | None (own state only) | Not affected | Kept |
| Free-for-all loot | Roster or team change, `/hb ffa` | Loot method, leader | Roster change; `/hb ffa` | Switches free for all to group loot, unless the leader picked free for all by hand; `/hb ffa` warns | Changed for #7 |
| Leave with leader | Leader leaves the group | `LeaveParty` on the follower | Leader leaves | Only when the stored leader leaves | Off by default; kept |
| Follow flights | Leader takes a flight (`P`) | `TakeTaxiNode` on the follower, once its flight map is open | Leader's flight; follower opens its map | Only from the stored leader | Owner decision: kept |
| Release / Rezz team | Leader clicks the buttons (`D`) | `RepopMe`, `AcceptResurrect`, `RetrieveCorpse` on the follower | Leader's click | Only from the stored leader | Owner decision: kept |
| Team offer / sync | `/hb team`, Send team, options button | Team list on every toon | Leader's click; followers accept a new leader in a popup | New members need a confirmation popup on the leader | Changed for #7 |
| Follow, focus, stats, errors | Local events | Group addon messages | None | Outsiders' messages ignored; outsiders with addon tools can read them | Kept; see privacy |
| Whisper forwarding | Whisper from outside the team | Addon whisper to the leader | Stranger whispers | Not affected (addon whisper, never the group) | Kept |
| Reply relay | Leader replies (`Y`) | Chat whisper from the follower to the stranger | Leader types the reply | Only from the stored leader | Kept; chat, not gameplay |
| HoTs, required buffs, aura windows | Unit aura events, 1 s timer | Display only | None | Game data about group members | Display only; restricted data shows unknown |
| Incoming heals, cast bars, mana timer | Unit events | Display on the team frame only | None | Game data about group members, as Blizzard's own frames show it | Display only; secret values never computed with |
| Share UI layout | Leader confirms a popup | Display settings and positions on followers | Leader's click | Whisper to team members only; followers accept only from their leader, can turn it off and undo | Display only; no gameplay or team settings |
| Abandon quest on team | Leader abandons a quest, then confirms a popup | Followers abandon the same quest | Leader's Yes | Followers act only on their stored leader's message, only for a quest they have; follower setting turns it off | Owner-requested 2026-11-16 |
| Take over as leader | A key press or /hb lead on the new leader | The leader name on every toon with the same team | That toon's own press | Sender must be a team member in the group with the same team; newest wins; roles and order unchanged | Leader name only |
| Follow / assist keys | The player's key press | /follow or /assist by name | The player's own press | Set out of combat; nothing solo, in raids, in mixed groups or on the leader | Never pressed by HaploBox |
| Assist-or-cast spells | The player's own key press | Cast at the leader's target, or a heal on the leader | The player's own press | Off after login and in solo, raid, mixed groups and on the leader; secure code disarms damage spells on any group change in combat; no macro edits | Not yet checked in the game |
| Quest tracker hiding | Option | Hide Blizzard's tracker | None | Not affected | Kept |

Not built and not approved by this review: leader handover by window switch
(#4), node sharing (#5), solo-safe assist macros (#8). Their issues carry the
research. UI-only work (#6, #9 to #14) does not depend on these decisions.

## Trusted roster (#7)

- The team is the stored leader plus the team list. A stored role alone no
  longer makes a name part of the team.
- Building the team from the group names every member who is not on the team
  yet in a popup on the leader. The popup is tied to the group it showed: if
  the group changes before the click, nobody is added.
- A follower takes a team only from its stored leader; a different leader needs
  the follower's own Accept (unchanged since 0.9.0).

## Loot (#7)

- The group is "team", "mixed" or "uncertain" (a name still shows as Unknown, or
  the member count does not match the units). This is worked out again on every
  roster change, team change and delayed check, by name, not by group size, so
  a same-size replacement is caught.
- Team: free for all, once per new roster or team. A method picked by hand stays
  until the group or team changes.
- Mixed: free for all becomes group loot, unless the leader picked the method by
  hand (owner decision, 2026-11-16: "if I set it myself HaploBox shouldn't
  overwrite"). By hand means `/hb ffa`, or a change in Blizzard's menu after a
  HaploBox change had taken effect; a request the server has not applied yet
  does not count. `/hb ffa` with outsiders present works and warns.
- The by-hand choice lasts until the group ends or a new team-only roster forms.
- Uncertain: nothing changes; it looks again every 2 seconds, up to 15 times, and
  again on the next roster change.
- Only the HaploBox leader who is also the group leader acts. The result is read
  back: "set", "could not set (it is ...)" or "cannot show whether it changed".
  Clients without loot methods (retail parties) are left alone.

## Privacy in mixed groups

Group addon messages (follow state, focus target, level, gold, bag space, cast
errors, flight destinations) go to the party channel. Outsiders cannot control a
toon with them, but anyone with an addon that listens to the HaploBox prefix can
read them. Whispers and replies already go by addon whisper only. Open question:
send stats only to the leader by addon whisper when the group is mixed.

## Tests

`tests/test_loot.lua` covers outsiders joining, same-size replacement, unknown
names, delayed checks, missing authority, refused and unsupported loot APIs,
`/hb ffa`, role-only names, the confirmation popup and cross-realm name forms.
`tests/test_protocol.lua` covers sender checks per message kind.

## Still needs the game

- Loot changes and read-back on Forever (16001), Classic Era and retail.
- Cross-realm names (#1): run `/hb who` on two connected realms and watch
  `/hb debug` for `ignored ... from` lines.

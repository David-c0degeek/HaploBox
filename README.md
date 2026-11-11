# HaploBox

A World of Warcraft addon for multiboxing a team: one leader and followers on separate accounts. Built for WoW Forever (interface 16001). It also loads on Classic Era and retail.

## What it does

- **Follow alerts:** when a follower stops following, the leader sees a raid-warning style message on its own screen ("Haplina Nightheart stopped following!") and hears a sound. The followers also play a sound when they start and stop following. Nothing is sent to group chat.
- **Invites:** followers accept group invites from the leader.
- **Quests:** followers accept quests that a team member shares. The leader shares every quest it accepts; set `all` to make every toon share. Quests received from a player are never shared back. A failed share plays a sound and prints the reason.
- **Loot:** the leader sets free-for-all loot when the group changes, and on `/hb ffa`. The `/ffa` slash command does not exist on WoW Forever.
- **Cast errors:** followers send errors like out of range, line of sight, out of mana or not in front to the leader, which prints them in chat.
- **Role checks:** group finder role checks are answered with the toon's team role.
- **Optional:** followers leave the group when the leader leaves, and passenger-mount sounds.

All communication uses a hidden addon channel (`HaploBox`). The addon does not touch protected or Edit Mode frames, so it cannot taint the UI.

## Setup

The `multibox-team-setup` skill writes the team (leader and roles) into each account's `HaploBox.lua` SavedVariables. To set it by hand in game:

```
/hb leader            (with the leader targeted, or /hb leader Haplina Wildheart)
/hb role tank|healer|dps
```

## Commands

| Command | |
|---|---|
| `/hb status` | Leader, role, loot method |
| `/hb ffa` | Free-for-all loot (group leader) |
| `/hb share` | Share every quest in your log with the group |
| `/hb sound <event> <value\|off>` | Change a sound |
| `/hb test <event>` / `/hb test alert` | Try a sound or the leader alert |
| `/hb who` | How the game names you and your target |
| `/hb options` | Options panel |
| `/hb debug` | Debug output |

Sound events: `followOn`, `followOff`, `leaderAlert`, `shareError`, `inviteAccept`, `mountOn`, `mountOff`. A sound value can be:

- a SOUNDKIT name, such as `RAID_WARNING` or `READY_CHECK`;
- a sound kit id, such as `8959`;
- `file:<fileID>`;
- a path such as `Interface\AddOns\HaploBox\Sounds\stop.ogg`. Put your own `.ogg` or `.mp3` files in `Sounds\`.

## Install

The WoW AddOns folder links to this repo:

```
mklink /J "C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\HaploBox" "D:\Repos\HaploBox"
```

Restart the game after adding new files. `/reload` is enough for Lua changes.

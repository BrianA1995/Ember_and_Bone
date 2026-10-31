# Playtest bugs and fixes

Found by playing the real game (godot-ai, a 2-player split-screen run, then a gallery scene that shows every
monster in the game window) and by the headless tests. Each entry says what was wrong, why, and how it was fixed.

## Fixed

### Mechanics

| # | Bug | Cause | Fix |
|---|-----|-------|-----|
| 1 | A candle went out with nothing in sight | A monster in a room nobody could see could still hit (the Lurker charged from out of sight). | `MonsterDirector.hit` refuses unless the monster's room is lit for that prisoner (`is_lit`). |
| 2 | The candle was snuffed again and again with nothing near | A Leech already clinging kept touching its host, so every `hit_immunity` seconds it snuffed the candle again (and re-connected `fell`, printing "Signal 'fell' is already connected"). | `Leech._touch` does nothing while it clings. One 180 s run went from 30 hits to 6. |
| 3 | Monsters chased from the dark | A prisoner with a lit candle could be hunted from any room. | `can_chase` is now `is_lit`: the prisoner's own room plus the rooms joined to it by an open doorway (candle lit), or only their own room (candle out). The dark ring stays; monsters there wander until the light reaches them. |
| 4 | The Lurker followed for a minute, hitting again and again | After a charge it rested 6 s and went back to stalking, and the grace period reset every time the prisoner stopped. | One 2 s grace period, then any movement or camera turn (small bumps allowed) sets it off. The charge hits everyone in the row or column, then that Lurker fades out. It leaves if the prisoner stays still beside it (4 s), and gives up after 40 s. |
| 5 | Far too many Lurkers | They were picked by weight like any monster, with no limit. | `kind_limits` (one Lurker at once) and `kind_gaps` (90 s between Lurkers). Other Lurkers still spawn later. |
| 6 | A monster stayed after its room was gone | Removal relied on a signal, and a monster's room was only noticed when that signal arrived. | `Monster._physics_process` also checks `room_exists` every tick and fades out if there is no room under it. |
| 7 | The spider spun a web in most rooms and followed like a dog | `web_chance` was 0.7 and it hunted for ever. | `web_chance` 0.1; a spider that has not snuffed anyone gives up after `prowl_seconds` (30 s). |
| 8 | The spider rose through the air on its way to its web | It started climbing while still walking to the web, so it rose in the middle of the room. | `_hang` walks along the floor and only climbs once it is at the web. |
| 9 | Rooms around the player did not change when the candle went out | `set_candle_lit` no longer changed anything. | When the candle goes out, `change_distance` shrinks to the dim sight range, so the rooms the player can no longer see are replaced (still lit for the game, still able to hold monsters). |

### Visual

| # | Bug | Cause | Fix |
|---|-----|-------|-----|
| 10 | A hint ran off the edge of a split-screen half ("...find a teammate's light, match") | HUD labels did not wrap, so a long line pushed past the pane. | `EscapeHud._label` wraps words. Checked in the 2-player game: the hint now takes two lines above the pack. |
| 11 | The Lurker's head and red eyes were buried in its body | The body capsule was 2 m tall and the head sat inside its top. | Shorter torso, head clear above the shoulders, bigger glowing eyes. |

## Seen and left alone
- A snuffed solo prisoner with no matches or spare candle stays in the dark until they find one (relight by themselves is off on purpose).
- The encounter bot is lit and hit about once every 17 s over 4 minutes in one run (14 hits, mostly Crawlers, Moths, Leeches and Weavers). That is a balance question, not a bug; the tension director gives a breather after each hit.
- Hint text names the buttons of the controller saved for that slot, so a keyboard player never sees "Hold A". If a saved gamepad is set for P1 the hints say so.
- Several `monster_test` checks depend on the random maze and fail now and then: the web check, "hidden room", the thief-walks-to-the-key check, and (with a poor maze) the Director/Mimic/relighting group. They were not caused by this work, but this has not been proven by running the older code.

## Not covered by this playtest
Matches were checked (a match relit the candle and used one). Lamp, string, chalk, walkie-talkie, keys and the leech in a live game were not reached by hand; they are covered by the headless tests only.

## How to look at the monsters
Run `debug/monster_gallery.tscn` in the editor (not headless). It shows each monster in front of the prisoner for 5 s, the Weaver on the floor, a wall and the ceiling.

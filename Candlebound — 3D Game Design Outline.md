# Ember & Bone — 3D Game Design Outline

Oct 18, 2026 · @Brian Allen

## Concept and pillars

*Ember & Bone* (working title) is a real-time 3D co-op horror game: 1–8 players online, or 1–4 in local split-screen, explore a monster-infested labyrinth that only exists inside their candlelight. It borrows one idea from The Night Cage — the maze appears as you walk and falls away behind you — and builds a live action game around it.

**Pitch:** You wake naked in a stone labyrinth holding a candle. Corridors rise out of the dark as you move and crumble into nothing once no light touches them. Things are hunting you. Find the keys, find a gate, and get out together before the wax runs out.

**Design pillars**

- **The light is the map.** The labyrinth is generated live around each player's light and erased when no one can see it. No two runs, and no two minutes, look the same.
- **Hunted, not fighting.** Monsters can't be killed. You survive by hiding, breaking line of sight, using light and darkness, and dropping the floor out from under them.
- **Spread out or stick together.** Splitting up reveals more maze and finds keys faster; staying together keeps everyone lit and revivable. Every run is a negotiation between the two.
- **Readable dread.** Every threat (cracking floors, a monster's charge lane, guttering wax) has a clear sound and visual tell, so deaths feel earned.

## Core loop and run structure

A run is a single 20–35 minute escape: wake, explore, gather keys, survive the hunt, open a gate.

**Moment to moment (every few seconds)**

1. Move into the dark; corridors build themselves at the edge of your light.
2. Read what appears: a key alcove, a cracked floor, a sound behind a wall.
3. React: grab, hide, sprint, shield your flame, call your team.
4. Behind you, unlit corridors crumble — routes close, and so do the paths monsters use.

**Over a run**

1. **Wake** together in a ring-shaped start chamber that collapses about 30 s after the run begins, forcing everyone out.
2. **Scatter** to search for keys and wax.
3. **The hunt escalates:** monster count and aggression rise as keys are collected and as total wax drops.
4. **Regroup** at a gate with enough keys and enough living prisoners.
5. **Escape** through a final chase while the labyrinth collapses toward the gate.

**Win:** enough living prisoners stand at one gate holding the required keys between them (see Keys, gates and escape).

**Lose:**

- Too few prisoners left alive to open any gate
- Too few keys still exist in the labyrinth
- Every gate has been lost to the dark
- Every candle has burned out

The game checks these continuously and ends the run with a "The Cage keeps you" screen the moment escape becomes impossible.

## The living labyrinth

The labyrinth is a large hidden grid (about 41×41 cells of 4 m each for 8 players) whose contents are decided only when light first reaches a cell. Generation and collapse run continuously in real time.

**How it builds**

- Each cell is a modular corridor piece: dead end, straight, corner, T-junction, cross, or a special room.
- When a doorway enters someone's light radius, the cell beyond it is rolled from a weighted table and rises out of the dark (about 0.6 s of stone assembling).
- New pieces always connect to the doorway that revealed them, so the maze never dead-ends illegally.
- A seeded random generator drives every roll, so a seed reproduces the same run for bug reports and Daily Seed mode.

**How it collapses**

- A cell that no light has touched for 4 s starts to crack, then falls into the void 2 s later.
- A collapsed cell can be regenerated later, but as a *new* random piece — the maze behind you is never the same twice.
- Collapse is both danger and tool: it cuts off monsters chasing you, but also gates and keys you didn't reach.

**Special rooms (rolled rarely)**

| Room | What it does |
| --- | --- |
| Key alcove | Holds one key; floor collapses a few seconds after the key is taken |
| Gate chamber | Large room where the group escapes; unlimited capacity |
| Wax shrine | Refills candles once, then goes dark |
| Monster nest | Spawns a monster when lit; marked by scratches |
| Safe niche | Small side pocket monsters won't enter while your flame is lit |

**Hard limits:** the grid has an outer wall, so the maze is finite; the number of keys and gates per run is fixed at start (see Keys) so the generator can't starve the players.

## Candlelight

Your candle is your map, your health bar's partner and your clock. Light radius decides how much maze exists around you; wax decides how long you have.

**Light radius**

- Default radius: 1 cell in every direction along open corridors (not through walls, not diagonally around corners).
- **Shield the flame** (hold): radius shrinks to your own cell, you move slowly and quietly, wax burns at half rate. Used for hiding.
- **Raise the flame** (hold): radius grows to 2 cells and stuns monsters facing you, but wax burns 4× faster and the glow draws attention.

**Wax**

- Each prisoner starts with about 12 minutes of wax. It burns constantly; sprinting and raising the flame burn more.
- Wax drips can be found in corridors (+30 s) and at wax shrines (full refill, one use).
- A prisoner can **share wax** with an adjacent teammate (hold to transfer in 30 s chunks).
- At 60 s left the flame gutters, the radius flickers, and the music thins.

**Darkness**

- Anything outside every player's light is pure black void, not fog.
- When your wax runs out, you enter Lights Out (see Lights Out and revives).

## Movement, actions and items

Prisoners are weak and slow on purpose. Movement is grounded and readable; every action trades speed, noise and wax.

| Action | Speed | Noise | Cost |
| --- | --- | --- | --- |
| Walk | 2.5 m/s | Low | Normal wax burn |
| Sprint | 4.5 m/s | High | Stamina (6 s), extra wax burn |
| Crouch-walk | 1.2 m/s | None | Required to enter safe niches |
| Shield flame | 1.5 m/s | None | Tiny light, half wax burn |
| Raise flame | 2 m/s | Medium | 4× wax burn, stuns monsters facing you |
| Jump a gap | — | Medium | Clears a 1-cell pit with a running start; fail = fall |

**Interactions:** pick up keys and wax, share wax, relight a teammate, ping, push a loose stone to make noise elsewhere.

**Items (one slot each, found in the maze)**

- **Chalk:** mark walls; marks vanish when the cell collapses.
- **Pebbles:** throw to make noise and lure a monster away.
- **Bone whistle:** reveals the direction of the nearest key for 5 s, but monsters hear it too.
- **Spare wick:** relight yourself once without a teammate.

No weapons. The fantasy is escape, not combat.

## Monsters

The labyrinth is infested. Monsters roam the generated corridors in real time, can't be killed, and each type forces a different way of surviving.

| Monster | Behaviour | How to survive | Tell |
| --- | --- | --- | --- |
| **Lurker** (common) | Waits in dark side passages; charges in a straight line when a lit prisoner crosses its corridor | Break the line: turn a corner, drop a floor between you | Wet clicking, red streak along the floor before the charge |
| **Crawler** | Slowly stalks the loudest sound it hears | Shield your flame, crouch, throw pebbles | Dragging, scraping |
| **Moth** | Drawn to bright light; extinguishes candles it touches | Shield flame, hide in a safe niche | Fluttering, flame bends toward it |
| **Warden** (rare) | Patrols near gates once 2+ keys are collected | Lure it away, time your approach | Heavy footsteps, chains |
| **Mimic** | Copies a teammate's silhouette at the edge of light | Ping check: real teammates show a name tag | Missing name tag, wrong flame tint |

**Rules every monster follows**

- Monsters can only travel on existing corridors. When the cells they stand on collapse, they fall and are gone for good (respawning later from a nest).
- Raising your flame stuns a monster facing you for 2 s.
- A monster hit: the prisoner drops all keys on the spot (teammates can pick them up within 20 s) and enters Lights Out. A hit while already in Lights Out kills.

**Director AI** controls pressure: it tracks keys collected, wax left, and how long since the last scare, then spawns or pulls back monsters so runs have peaks and quiet valleys. Monster count scales with player count (see Multiplayer).

## Hazards and falls

The floor itself is the main environmental threat, and the main escape tool.

- **Cracked floors:** some corridor pieces (straights and key alcoves) are visibly cracked. They hold for 3 s after you step off, then collapse into a pit. Standing still on one for 3 s drops you through.
- **Pits:** block both prisoners and monsters. A 1-cell pit can be jumped with a running start; longer gaps can't.
- **Deliberate drops:** stamp (hold interact) on a cracked floor to collapse it early — the best way to cut off a chasing Lurker.

**Falling (the board game's pit jump, made live)**

1. You drop into black; your local light vanishes and nearby cells lit only by you start collapsing.
2. A 4 s freefall with a choice: steer toward one of the glowing breaks in the dark, each a landing spot along the labyrinth's outer edge.
3. You land hard (2 s stagger) in a freshly generated cell far from your team.
4. If no landing spot exists, you are lost to the dark and out of the run.

Falling is a desperate escape from a monster that also scatters the group — and the fall lands on a monster about 1 time in 10.

## Lights Out and revives

Getting hit, touched by a Moth, or running out of wax puts your flame out. You are not dead yet — but you are blind and fragile.

**While in Lights Out**

- You see only your own cell by the faint ember of the wick. Corridors lit only by you start collapsing.
- The cell under you begins to crack if you stand still for 5 s, so you must keep moving.
- One more monster hit kills you.
- After 90 s without a relight, the ember dies and you are dead.

**Relighting**

- A lit teammate stands next to you and holds interact for 2 s to touch flames; you come back with 60 s of wax (or your remaining wax, if it was a hit).
- A **spare wick** item lets you relight alone.
- A relit prisoner's corridors rebuild around them immediately.

**Dead prisoners** become drifting "ghost lights": they can't interact, but they can look around, ping, and talk on voice, so they stay part of the team. An optional *Second Wick* rule lets the group revive a ghost once per run at a wax shrine.

## Keys, gates and escape

Keys and gates are seeded into the labyrinth at the start of a run in fixed numbers, so the generator can't make a run unwinnable by bad luck — only players can.

| Players | Keys in the maze | Keys needed | Gates | Prisoners needed at gate |
| --- | --- | --- | --- | --- |
| 1 | 4 | 3 | 2 | 1 |
| 2–3 | 6 | 4 | 3 | 2 |
| 4–5 | 8 | 5 | 3 | 2 |
| 6–8 | 10 | 6 | 4 | 3 |

- **Keys** are carried on a cord and shown on your character. You can **hand a key** to an adjacent teammate (unlike the board game) so the group can consolidate before a dash.
- A key alcove that collapses before anyone takes its key loses that key for good.
- **Gates** appear as large chambers. Once enough keyholders and keys are inside, a 10 s unlock starts; monsters converge during it.

**Escape sequence:** the gate opens onto grey daylight and a final corridor run while the labyrinth collapses toward you. Prisoners who make it through escape; anyone left behind in Lights Out or too slow is lost. The run counts as a win if the minimum number of prisoners gets out.

## Multiplayer

The game supports 1–8 players online and 1–4 players in local split-screen on one machine. Both can mix: a couch of up to 4 can join an online lobby, as long as the lobby total stays at 8 or fewer.

**Online (1–8)**

- Host or join by invite, join code, or public lobby browser.
- Drop-in during the first 2 minutes of a run; after that, new players wait for the next run.
- If a player disconnects, their prisoner stands still with a shielded flame for 60 s so they can rejoin; after that it becomes a ghost light.
- Proximity voice chat: muffled through walls, cut to whispers in Lights Out, carried far in echo halls (which monsters also hear).

**Local split-screen (1–4)**

- 2 players: vertical split. 3–4 players: quadrants (the 4th quadrant shows the shared map when only 3 play).
- Each screen renders its own light radius; the labyrinth is shared, so one player's darkness can collapse corridors behind another.
- Performance budget is set for 4-way split on the lowest target platform from day one.

**Scaling by group size**

| Players | Labyrinth size | Monsters at once | Wax per prisoner |
| --- | --- | --- | --- |
| 1 | 21×21 | 2–3 | 14 min |
| 2–4 | 29×29 | 3–6 | 12 min |
| 5–8 | 41×41 | 6–10 | 11 min |

**Communication:** a ping wheel ("Key", "Monster", "Gate", "Wax", "Help", "Wait"), chalk marks, and a team status strip showing each prisoner's wax, keys and state.

## Camera and controls

First person by default for dread, with an over-the-shoulder third-person option. Split-screen defaults to third person, which reads better in small viewports.

| Action | Keyboard/mouse | Controller |
| --- | --- | --- |
| Move / look | WASD / mouse | Left stick / right stick |
| Sprint | Shift | Left stick click |
| Crouch | Ctrl | B / Circle |
| Shield flame | Hold right mouse | Hold LT / L2 |
| Raise flame | Hold Q | Hold RT / R2 |
| Interact (pick up, relight, share wax, stamp floor) | E (hold where needed) | A / Cross |
| Jump | Space | Y / Triangle |
| Use / throw item | F | RB / R1 |
| Ping wheel | Middle mouse | LB / L1 |
| Push-to-talk | V | D-pad down |

All controls are rebindable, and every local split-screen player can use any controller. Mouse and keyboard counts as one local player.

## Menus, screens and HUD

All four ways to play lead into one shared lobby, so solo, local and online use the same run setup.

&#91;embedded content: menu and screen flow · 4 ways to play\]

From the end screen the group can replay together or quit to the main menu.

**Screens**

- **Title screen:** a candle held in the dark; press any button. In split-screen, each controller presses to claim a slot.
- **Main menu:** Play, Tutorial, Daily Seed, Cosmetics, Codex, Options, Quit. Diegetic: options are scratched into a cell wall lit by your candle.
- **Lobby:** up to 8 player slots, up to 4 of them local; flame-tint picker; host sets difficulty, labyrinth size, seed, modifiers; ready-up per player. Online lobbies show join code and privacy (invite, friends, public).
- **Wake-up intro:** 10 s skippable shot of the prisoners waking in the start chamber.
- **Pause menu:** pauses only in solo; in co-op it opens over live play.
- **End screen:** who escaped, fell or died; keys found; wax used; time; seed to share; cinders earned.

**In-run HUD (minimal by default)**

- Candle with wax remaining (the candle physically shortens)
- Keys you hold and team keys vs keys needed
- Team strip: each prisoner's flame tint, state (lit, dark, ghost), wax and keys
- Gate compass only after a gate has been seen
- Context prompts: "Hold to relight", "Floor cracking", "Hand key"

**Accessibility:** colour-blind palettes for danger cues, subtitles and visual indicators for every sound cue, brightness floor so darkness never becomes unreadable, reduced camera shake on falls, hold-to-toggle options for all held actions.

## Art direction and audio

A stippled, high-contrast monochrome world: bone-white stone cut out of absolute black, warm candle orange as the only strong colour, red reserved for danger.

**Visuals**

- Real-time point light per candle; nothing renders outside the lit set, which also saves performance.
- Grain and stipple post-process to give an inked, hand-drawn feel.
- Corridors assemble stone by stone when revealed and crack, tilt and drop into the void when lost.
- Prisoners are pale, bald, featureless figures; each player picks a flame tint so teammates are recognisable at a glance.
- Monsters are mostly half-seen — limbs and teeth at the edge of the light.
- All art, creatures and names must be original; take the mood from the board game, not its illustrations.

**Audio**

- No music in the usual sense: low drones that rise with danger and thin out as wax runs low.
- Positional audio carries the game: stone grinding (new corridor), cracking (floor about to go), wind (open pit), each monster's own signature sound.
- The candle crackle is always with you; it sputters when low and goes silent in Lights Out.
- Short motifs for key pickup, gate reveal, and a teammate going dark.

## Modes, difficulty and progression

One core mode at launch — the escape run — with difficulty and modifiers for variety. Progression unlocks variety and cosmetics, never raw power.

| Difficulty | Wax | Monsters | Collapse delay | Helpers |
| --- | --- | --- | --- | --- |
| Kindled | +30% | −30%, slower | 8 s | Monster charge lanes shown, key compass |
| Standard | Base | Base | 4 s | Charge lanes shown briefly |
| Ember | −20% | +25% | 3 s | No lane hints |
| Ash | −30% | +50%, Mimics on | 2 s | No HUD wax number, permadeath (no Second Wick) |

**Other modes (launch or soon after)**

- **Tutorial run:** short guided labyrinth teaching one mechanic per area.
- **Daily Seed:** same labyrinth for everyone each day; leaderboard by time and survivors.
- **Custom run:** sliders for maze size, monster mix, wax, keys needed.
- **Versus (post-launch idea):** one player controls the monsters through the Director.

**Progression:** escapes earn cinders spent on candle styles, flame tints, prisoner markings, and starting-item loadouts (pick 1 of 2 items at the start). A lore codex unlocks monster entries and scratched-wall messages that explain who built the Cage.

## Technical architecture

The host's simulation owns the labyrinth, monsters and win/lose state; clients predict their own movement and render what the host tells them. The maze is data first, 3D second.

**Engine:** Unreal Engine 5 or Unity both handle 8-player co-op and 4-way split-screen; Unreal has built-in replication and strong lighting, Unity is lighter for a small team. Godot is possible but networking and split-screen need more custom work.

**Core systems**

| System | Responsibility |
| --- | --- |
| `LabyrinthGrid` | Cell data (piece, rotation, state, timers); seeded generation |
| `LightField` | Computes which cells every candle lights each tick |
| `RevealCollapse` | Generates newly lit cells, cracks and drops unlit ones |
| `WaxSystem` | Burn rates, pickups, sharing, Lights Out trigger |
| `MonsterAI` + `Director` | Per-monster behaviour trees; Director sets spawn and pressure |
| `PlayerController` | Movement, actions, items; client-side prediction |
| `RunState` | Keys, gates, prisoners, win/lose checks |
| `NetSync` | Replicates grid changes as compact events, not meshes |
| `SplitScreenManager` | Up to 4 local players, viewports, per-player audio listener |
| `UI / HUD` | Reads state, never writes it |

**Networking**

- Listen-server (one player hosts) for launch; dedicated servers only if a public matchmaking audience appears.
- Grid changes are tiny events (cell id, piece, rotation) — only monsters and players need high-frequency sync.
- Steam Networking or Epic Online Services for lobbies, invites, join codes and NAT traversal; aim for cross-play later.

**Performance:** only lit cells and their neighbours exist as meshes, so the scene stays small even on a 41×41 map. Budget 60 fps for 1 player and 30+ fps for 4-way split on the minimum spec.

## Production roadmap

The riskiest idea is the maze that builds and erases itself in real time, so prove that alone before adding players or art. Phase lengths depend on team size and are left open.

&#91;embedded content: production roadmap · 5 phases, 4 gates\]

Each diamond is a go/no-go playtest; build networking and split-screen support into the code from phase 1 even though they ship in phase 3.

## Open questions

- [ ] **Rights:** the idea of a maze that exists only in your light can be borrowed, but The Night Cage's name, art and text belong to its creators. Keep the new title and fully original art, and check with a lawyer before release.
- [ ] First or third person as the default for single-screen play?
- [ ] Is a 1-cell light radius too tight for real-time play? Prototype 1 vs 1.5 vs 2 cells.
- [ ] Should keys be transferable (current draft) or personal like the board game?
- [ ] Target platforms: PC first, or PC + consoles at launch (affects split-screen performance)?
- [ ] Engine choice and team size — these set every phase length on the roadmap.
- [ ] Is Versus mode worth designing for early, or strictly post-launch?

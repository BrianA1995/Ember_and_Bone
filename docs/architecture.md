# Architecture

The code is a tree. Every system is made, wired and owned by the one above it, and you can follow any
interaction by reading down from the top. Nothing finds another system through a global group or a scene
lookup; if a system needs another, its parent hands it over in `setup()` (or sets a variable before the node
enters the tree).

```
GameSession (autoload)          menu <-> game scenes, nothing else
├─ MainMenu                     MenuShell + MenuBackdrop (the maze behind the title screen)
└─ LocalGame  (game/game.tscn)  the composition root of a running game
   ├─ MazeManager               the world: grid, view, lights, seam wrap, collapse. Knows nothing above it.
   ├─ Players / CameraRigs      one body + one rig + one pane per slot (made here, wired here)
   ├─ SightMap                  which rooms each prisoner sees, worked out once and shared
   ├─ Pursuit                   the tag chase helper
   ├─ Mode: TagMode | EscapeRun the rules of the round
   │   └─ ItemBag, ItemScatter, ItemUse, MonsterDirector, Relighting, WaxShrines, SightGate (escape only)
   ├─ SplitScreen               one pane per player
   └─ PauseMenu                 MenuShell with the pages, given the maze and the rigs
```

## Rules

1. **Parents make, children receive.** `LocalGame` creates every system and passes what each needs. A child
   never calls `get_first_node_in_group` / `get_nodes_in_group` to find a system.
2. **Calls go down, signals go up.** A parent calls its children; a child tells its parent through a signal
   (`CameraRig.mode_changed`, `EscapeRun.run_won`, `MazeManager.maze_rebuilt`).
3. **The maze knows nothing about players.** `MazeManager` lights the world around the lights registered with
   `add_light()` (a player, a lamp, a point on a string). It never imports a player or a screen.
4. **One answer, one place.** "Which rooms does this prisoner see?" is `SightMap`; "what layer is this?" is
   `PhysicsLayers`. A second copy of either is a bug.
5. **Work happens only where something is going on.** A cracked floor sleeps until a body is in its detector;
   sight is recomputed only when a prisoner changes room or light, or the maze changes shape.

## Physics layers (`core/physics_layers.gd`)

`WORLD` (1) is the maze. `BODIES` (2) are the prisoners. A camera, a sight line or a ground probe that should
only meet the maze asks for `WORLD`. This is what stopped a teammate behind you pulling your third-person camera
in against them (they blinked in and out of view).

## Groups that are left

Only registries the owning class defines and documents: `SightGate.GROUP` (things shown only in a seen room),
`CrackedFloor.GROUP` (tiles near a stamping body), and `players` (debug tools only).

## Tests

Every test is a scene: `godot --headless --path . res://debug/<name>.tscn`. `camera_clip_test` guards the
blinking fix; `cracked_floor_test` the floor detector; `monster_test`, `escape_test`, `item_test`, `tag_test`,
`local_coop_test`, `wrap_test` the systems. `debug/autoplay.tscn` plays a whole solo run in the real window.

## Online play (planned): rules to code by now

The goal is one machine hosting and up to 16 players joining. None of it is built yet; these rules keep the
code from making it hard. The host is authoritative: it runs the maze, the monsters, the items and the rules.
Clients send what the player wants to do and draw what the host tells them.

1. **Simulation and presentation are separate.** A player is a *body* (host: position, candle, falls, hits),
   an *input source* (who is steering it) and a *view* (camera rig, HUD, pane: this machine only). A host with no
   screen must be able to run the whole game without ever creating a view.
2. **Input is data, not a device.** The body asks its input source for this tick's move, look, sprint and button
   presses. Sources: local (keyboard / pad), remote (commands from the network), bot (the autoplay).
3. **Two different numbers, never one.** A *local slot* (0-3) is a pane and an input device on this machine: at
   most four per machine (split screen). A *player id* (0-15) is a prisoner in the game: at most sixteen over all
   machines. They are different things and the code must never use one for the other. Everything about the
   game (keys held, points, who is it, colours, the roster) is indexed by player id and sized by the roster, never
   by a fixed four. Everything about this machine's screen and controls (panes, HUDs, input actions) is indexed
   by local slot. A prisoner who is not on this machine has a player id and no local slot.
4. **Hiding your own body is a local-slot matter.** First-person cameras leave out the body of their own local
   player, so the render layer for that is keyed by local slot (four layers, enough for one machine). A body
   with no local slot (a remote prisoner) is drawn by every camera on this machine and needs no layer.
5. **The maze is replicated by its events** (`cell_added`, `cell_removed`, `side_sealed`). It grows with the
   lights, so it cannot be rebuilt from the seed alone. Each client is sent only the rooms its player can see
   (that is `SightMap`).
6. **Rules and monsters run on the host only.** The escape run, tag mode, the monster director and the item
   scatter never run on a client; clients get state (keys held, who is it, where each monster stands) and show it.
7. **A menu never pauses the world.** Online the world keeps running, so the pause menu is an overlay and the
   host decides whether a local game pauses.
8. **Time is the host's.** Anything that counts seconds (the start collapse, a web, a lamp, a Lurker's grace)
   counts them on the host, from its physics ticks.

## Split screen and online together

A machine can host or join with up to four local players, alongside the remote players of other machines (for
example two friends on one couch joined by twelve online, sixteen in all). So the roster of a running game is a
list of prisoners, each with a player id and an input source; the prisoners whose source is *local* also have a
local slot, a pane and a HUD on this machine, and the rest are remote bodies this machine only draws. The host
runs the simulation for all sixteen whichever machine they sit at.

## The candle's wax

A candle's life is `Wax` (player/wax.gd), owned by the `Player` that carries it: the game setup chooses how long
it burns (`GameSettings.candle_minutes`, 0 never) and `EscapeRun.restart` hands every prisoner a fresh one. It
burns while the flame is held (faster raised, slower put away, not at all blown out). The candle shows it by
shortening and guttering; nothing prints a number. When it is gone the prisoner is in the dark, slow and cannot
sprint, and only a refill helps: a spare candle (`Relighting`) or a wax shrine (`WaxShrines`, dealt into the maze
by the candle's life). The raised flame is blown out with the use button (`ItemUse`), and a match lights it again.

## Special rooms and what they do

`key_alcove` / `gate_chamber`: `EscapeRun`. `wax_shrine`: `WaxShrines`. `safe_niche`: monsters cannot go in, hit
anyone in it or be placed there while a prisoner inside has a lit flame (`MonsterDirector.is_sanctuary`).
`echo_hall`: every sound a prisoner makes in it is louder, and standing still in it is heard
(`MonsterDirector.sounds`; only the Crawler listens so far). The start chamber is also a sanctuary.

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
   │   └─ ItemBag, ItemScatter, ItemUse, MonsterDirector, Relighting, SightGate (escape only)
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

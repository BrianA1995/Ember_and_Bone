class_name PhysicsLayers
extends RefCounted
## The physics layers (bit masks), so nobody has to remember what layer 1 or 2 means.
##
## WORLD is the maze: floors, walls, props. BODIES are the prisoners. A camera, a line of sight or a
## ground probe that should only ever meet the maze asks for WORLD; a prisoner collides with both.

const WORLD := 1
const BODIES := 2

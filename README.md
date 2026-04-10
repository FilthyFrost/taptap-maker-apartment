# TapTap Maker Apartment Generator

Lua procedural apartment layout generator for TapTap Maker (UrhoX engine). Generates 3-bedroom, 2-living-room villa floor plans with automatic furniture placement.

## Features

- Force-directed room layout algorithm (ref: [Magnetizing FloorPlanGenerator](https://github.com/hellguz/Magnetizing_FloorPlanGenerator))
- 9 rooms: living room, dining room, kitchen, master bedroom, 2 secondary bedrooms, master bath, public bath, corridor
- Automatic furniture placement with spatial rules
- Door clearance zones (no furniture blocking doors)
- Passage pathfinding (ensures rooms are accessible)
- 3.5m ceiling height
- 50m x 35m apartment (half a football field)
- Pure Lua, no external dependencies
- Outputs layout data table for UrhoX/TapTap Maker

## Quick Start

```bash
# Generate a layout (seed 42)
cd apartment_generator
lua main.lua 42

# Export to file
lua main.lua 42 my_apartment.lua

# Run tests
lua test.lua
```

## Output

The generator outputs a Lua table with:
- Room positions and dimensions (meters)
- Wall segments (exterior + interior)
- Door positions on shared walls
- Window positions on exterior walls
- Furniture placements per room (type, position, size, rotation)

## Using with TapTap Maker

See `skill-apartment-builder.md` for the complete guide on turning layout data into a 3D UrhoX scene with walls, floors, ceilings, doors, and furniture.

```lua
-- In your TapTap Maker game script:
local layout = dofile("apartment_layout.lua")
BuildApartment(layout)  -- One function call builds the entire apartment
```

## Spatial Rules

The generator enforces these rules (solving common TapTap Maker AI mistakes):

| Rule | Description |
|------|-------------|
| Door clearance | 1.5m keep-clear zone on both sides of every door |
| Passage width | Min 0.8m walkable path from door to room interior |
| Ceiling height | 3.5m (higher than standard 2.7m) |
| Furniture spacing | Min 0.4m gap between furniture pieces |
| Window clearance | No tall furniture within 0.8m of windows |
| Wall placement | Furniture against walls with 0.05m gap |

## References

- [Magnetizing FloorPlanGenerator](https://github.com/hellguz/Magnetizing_FloorPlanGenerator) - Force-directed layout algorithm
- [ProcTHOR](https://github.com/allenai/procthor) - Furniture placement rules
- [Housify](https://github.com/Ryan-M3/housify) - Squarified treemap + corridor generation
- [Graph2Plan](https://github.com/HanHan55/Graph2plan) - Room adjacency graph model

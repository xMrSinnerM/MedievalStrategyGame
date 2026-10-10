# Medieval Strategy

A medieval strategy game that combines castle building and an economy with a
campaign world map. **Phase 1, the world map, is done; phase 2, the castle
and its economy, is under way.** It is free of pay-to-win: nothing that could
ever be bought gives a gameplay advantage. It's built in **Godot 4.3+** (GDScript; tested in 4.3 and 4.7.2) and targets PC.

The continent, its names and its factions are original to this game.

## Running it

1. Install [Godot 4.3 or newer](https://godotengine.org/download) (standard
   build, not .NET).
2. In the Project Manager, choose **Import** and pick `project.godot`.
3. Press **F5**. The first time you open the project, Godot imports the world
   files; that takes a few seconds.

| Input | Action |
| --- | --- |
| Left click on the ground or a settlement | Send your party there |
| F | Centre the camera on your party |
| WASD / arrow keys, or left/middle drag | Pan |
| Q / E, or right drag | Rotate |
| Mouse wheel | Zoom (the camera tilts towards top-down as you zoom out) |
| M | Toggle the parchment map |
| Home | Recentre |
| F1 | Hide the help panel |

Your warband starts just outside Highford, with a gold ring around it. Click
anywhere to march there: a dashed line shows the route, and the help panel says
what ground you are crossing. The faction lords ride between their own towns
and castles on their own.

Zoom all the way out and the map turns into a parchment strategic map with
faction territories, roads and settlement marks.

## Editing the world

The world lives in plain files that you can edit:

| File | What it is | How to edit |
| --- | --- | --- |
| `world/heightmap.exr` | 1025 x 1025 single-channel float heightmap, 0 = sea floor, 1 = `max_height` | Krita, GIMP or Photoshop (32-bit float) |
| `world/heightmap_preview.png` | 8-bit preview of the heightmap | For viewing only; the game doesn't read it |
| `world/biome_mask.png` | Painted regions: **red** = desert, **green** = forest, **blue** = snow | Any image editor |
| `world/rivers.json` | River paths: `[x, z, water height, width]` per point | Text editor |
| `data/terrain_config.json` | Seed, map size, sea level, snow line, tree density, fog | Text editor |
| `data/factions.json` | Factions: name, colours, banner, home region, building style | Text editor |
| `data/settlements.json` | Towns, castles and villages: name, type, owner, position, rotation, and the lord a village belongs to | Text editor |
| `data/parties.json` | Parties on the map: name, faction, starting settlement, troops; one is marked `"player": true` | Text editor |
| `data/roads.json` | Roads between settlements: `main` or `track`, as `[x, z]` point lists | Text editor, or regenerate |

Coordinates are in map units: x runs west to east and z runs north to south,
both from 0 to 2048. The sea level is at 40 and the highest peaks reach about
300.

### Generating a new continent

The generator builds the heightmap, biome mask and rivers from the seed in
`data/terrain_config.json`:

```
godot --headless --path . --script res://scripts/tools/generate_world.gd
```

It takes about 15 seconds. **It overwrites the three world files**, so hand
edits to them are lost. Rivers are carved into the heightmap, so if you
reshape the land under a river, either repaint around it or regenerate.

### Placing settlements and roads

Two more tools fill in the settlements and plan the roads on the current
terrain. Run them in this order after generating a continent:

```
godot --headless --path . --script res://scripts/tools/place_settlements.gd
godot --headless --path . --script res://scripts/tools/generate_roads.gd
```

`place_settlements.gd` picks flat spots inside each faction's region (towns
near the realm's heart and rivers, castles on high ground towards the borders,
villages around their lord) and **overwrites `data/settlements.json`**.
`generate_roads.gd` joins towns and castles with main roads and every village
to its lord with a track, avoiding steep ground and crossing rivers as rarely
as it can; it **overwrites `data/roads.json`**. To move a settlement by hand,
edit its position in `settlements.json` and run only the road tool again.

## Castle economy

Your castle produces **wood, stone, food and gold** in real time, including
while the game is closed: when you start it again, the castle catches up on the
time that passed. The help panel on the world map shows your stock, storage
limit and production per hour.

### Castle screen

Press **C** or click **Your castle** on the world map to walk into your castle;
press C again or click **World map** to go back. Both screens stay loaded, so
switching is instant and the map keeps its camera and your party's route.

- **Build menu** (bottom): pick a building, then click a free spot on the grid.
  The building follows the mouse in green where it fits and red where it
  doesn't. Right-click or Esc stops placing. Greyed-out buttons tell you why
  in their tooltip (not enough resources, all builders busy, keep too low).
- **Click a building** to see what it does now and at the next level, upgrade
  it, move it (free) or cancel its construction (75% refunded). Click the wall
  to upgrade the castle's defence.
- **Under construction** (top left) lists every job with a countdown, and a
  timer floats over each building site.
- Camera: WASD or drag to pan, Q/E or right-drag to rotate, wheel to zoom.
- NPC castles open in the same screen read-only, ready for step 3.

- **Buildings** are defined in `data/buildings.json`: keep, castle wall,
  woodcutter, quarry, farm, house (taxes in gold) and storehouse. Each has a
  level-1 cost, build time and output, and a growth factor per level
  (`value x growth^(level - 1)`), so balancing means changing a few numbers.
- **The keep sets the limits**: other buildings can go up to twice its level,
  it decides how many of each you may build, and it adds builders (one at
  first, more at keep levels 3 and 5). Builders are the only way to build
  faster; there is no premium currency and nothing to buy.
- **Storage** comes from the keep and storehouses and caps every resource.
- **Saving** is automatic every 30 seconds and on quit, to `savegame.json` in
  the game's user folder (`%APPDATA%\MedievalStrategy` on Windows). Delete it
  to start over.
- `CastleState` runs one castle and is written so NPC castles can use exactly
  the same code later.

Run the economy tests with:

```
godot --headless --path . --script res://tests/test_economy.gd
```

## Project layout

```
data/        JSON: terrain config, factions, settlements, roads, parties, buildings
world/       heightmap, biome mask, rivers
scenes/      main.tscn -> world_map/world_map.tscn and castle/castle_view.tscn
scripts/
  core/      main (switches map and castle), GameData, EventBus and Economy autoloads, map style
  economy/   castle economy: building rules, castle state
  castle/    castle screen: view, camera, placeholder building models
  terrain/   generator, terrain data and queries, terrain/water/river/tree layers
  world/     world map root, settlements, banners, roads, parchment overlay
  camera/    campaign camera
  ui/        world map HUD, castle HUD
  tools/     command-line tools (world generator, settlements, roads)
shaders/     terrain, water, river, tree, prop, flag, route, parchment, castle ground (+ shared fog include)
tests/       headless tests (economy)
```

How the parts work:

- **Terrain** is 16 x 16 flat chunk meshes that `terrain.gdshader` lifts with
  the heightmap texture and colours by height, slope and biome (grass, dirt,
  rock, sand, desert and snow). `TerrainData` holds the same heights on the CPU
  for gameplay queries: `get_height`, `get_slope`, `is_water`, `get_biome` and
  `raycast` (for mouse picking).
- **Water**: the sea is one large plane whose shallows and foam come from the
  heightmap. Rivers are ribbon meshes that follow `rivers.json`.
- **Trees** are placeholder low-poly meshes scattered in clusters from the
  biome mask, drawn with MultiMesh and faded out with distance.
- **Fog**: every map shader shares `shaders/includes/map_common.gdshaderinc`,
  which fades the map edges and distant ground into a warm haze.
- **Settlements** are placeholder models built from boxes, cylinders and roofs
  (`settlement_models.gd`) in each faction's wall and roof colours, standing on
  a small earth plinth. Towns have a ring wall and houses, castles a square
  wall and keep, villages a handful of houses. Each flies its faction's banner,
  drawn in code from `factions.json` (`banners.gd`), and has a name label that
  stays the same size on screen. Village names hide when you zoom out, then
  castle names; town names always show.
- **Roads** are painted into the terrain as packed dirt from a mask that
  `RoadNetwork` builds at load time. Bridges go up where a road crosses a
  river, and trees keep clear of roads and settlements.
  `GameData.roads.is_on_road(x, z)` tells whether a spot is on a road.
- **Parties** (`party.gd`, `parties_layer.gd`) find their way with
  `NavGrid`, an A* grid over the whole map in 4-unit cells. Each cell has a
  travel cost: roads 0.6, plains 1.0, desert and snow 1.4, forest 1.8, more on
  hills, 3.0 to wade a river without a bridge; water and mountains are
  impassable. The same cost slows a party down while it walks, so routes
  prefer roads and bridges. Routes are straightened where that doesn't leave
  cheaper ground, then rounded off. Parties grow as you zoom out so they stay
  visible, and disappear inside settlements.
- **Parchment map** fades in near maximum zoom. Each spot belongs to the
  faction of the nearest settlement (towns reach further than castles, castles
  further than villages), worked out in the shader, so borders will follow when
  a settlement changes hands. Roads are dashed, towns are ringed discs, castles
  squares and villages dots.

## Status

- [x] Architecture plan
- [x] Terrain, water, rivers, trees, fog, camera, parchment map
- [x] Settlements (towns, castles, villages), banners, labels, roads
- [x] Parties with pathfinding
- [x] Castle economy: resources, buildings, build timers, offline progress, saving
- [x] Castle screen: place and upgrade buildings
- [ ] Your castle and NPC castles on the world map

## Known limitations

- The world files are read straight from disk, which works when running from
  the editor. Exported builds will need them added as resources; that's left
  for when we set up exports.
- The look is tuned for the default Forward+ renderer. The Compatibility
  renderer works but skips ambient occlusion.

## Free asset packs that fit the style

Placeholder primitives stand in for art. These CC0 packs would fit:

- Trees and nature: Quaternius Ultimate/Stylized Nature, Kenney Nature Kit
- Castles and walls: Kenney Castle Kit
- Village and town buildings: Quaternius Medieval Village, KayKit medieval packs
- Ground and parchment textures: ambientCG, Poly Haven
- Fonts (SIL OFL): IM Fell English, Cinzel

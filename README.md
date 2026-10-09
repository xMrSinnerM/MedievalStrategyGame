# Medieval Strategy: World Map Prototype

A medieval strategy game that combines castle building and an economy with a
campaign world map. This repository holds **phase 1: the world map
prototype**. It's built in **Godot 4.3+** (GDScript; tested in 4.3 and 4.7.2) and targets PC.

The continent, its names and its factions are original to this game.

## Running it

1. Install [Godot 4.3 or newer](https://godotengine.org/download) (standard
   build, not .NET).
2. In the Project Manager, choose **Import** and pick `project.godot`.
3. Press **F5**. The first time you open the project, Godot imports the world
   files; that takes a few seconds.

| Input | Action |
| --- | --- |
| WASD / arrow keys, or left/middle drag | Pan |
| Q / E, or right drag | Rotate |
| Mouse wheel | Zoom (the camera tilts towards top-down as you zoom out) |
| M | Toggle the parchment map |
| Home | Recentre |
| F1 | Hide the help panel |

Zoom all the way out and the map turns into a parchment strategic map with
faction territories.

## Editing the world

The world lives in plain files that you can edit:

| File | What it is | How to edit |
| --- | --- | --- |
| `world/heightmap.exr` | 1025 x 1025 single-channel float heightmap, 0 = sea floor, 1 = `max_height` | Krita, GIMP or Photoshop (32-bit float) |
| `world/heightmap_preview.png` | 8-bit preview of the heightmap | For viewing only; the game doesn't read it |
| `world/biome_mask.png` | Painted regions: **red** = desert, **green** = forest, **blue** = snow | Any image editor |
| `world/rivers.json` | River paths: `[x, z, water height, width]` per point | Text editor |
| `data/terrain_config.json` | Seed, map size, sea level, snow line, tree density, fog | Text editor |
| `data/factions.json` | Factions: name, colours, banner, home region | Text editor |

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

## Project layout

```
data/        JSON: terrain config, factions (settlements and roads come next)
world/       heightmap, biome mask, rivers
scenes/      main.tscn -> world_map/world_map.tscn
scripts/
  core/      GameData and EventBus autoloads, shared map style
  terrain/   generator, terrain data and queries, terrain/water/river/tree layers
  world/     world map root, parchment overlay
  camera/    campaign camera
  ui/        debug HUD
  tools/     command-line tools (world generator)
shaders/     terrain, water, river, tree, parchment (+ shared fog include)
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
- **Parchment map** fades in near maximum zoom. For now, territories come from
  each faction's `region_center`; once settlements exist they will come from
  settlement ownership.

## Status

- [x] Architecture plan
- [x] Terrain, water, rivers, trees, fog, camera, parchment map
- [ ] Settlements (towns, castles, villages), banners, labels, roads
- [ ] Parties with pathfinding

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

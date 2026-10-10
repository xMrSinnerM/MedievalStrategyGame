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
| Left click on a castle or a lord's party | Open its panel (travel, look inside, attack) |
| F | Centre the camera on your party |
| WASD / arrow keys, or left/middle drag | Pan |
| Q / E, or right drag | Rotate |
| Mouse wheel | Zoom (the camera tilts towards top-down as you zoom out) |
| M | Toggle the parchment map |
| Home | Recentre |
| F1 | Hide the help panel |
| K | Diplomacy screen: wars, peace, gifts |
| Esc | Pause menu: save, settings, main menu, quit |

Your warband starts just outside Highford, with a gold ring around it. Click
anywhere to march there: a dashed line shows the route, and the help panel says
what ground you are crossing. The faction lords ride between their own towns
and castles on their own, and lords at war fight when they meet (see Battles).

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

## Menus and settings

The game opens on a title screen: **Continue** the game you played last, start
a **New game** in one of three save slots (it asks before replacing a slot),
**Load** or delete a game from the slot list (each slot shows its keep level,
castles, soldiers and when it was saved), change the **Settings** or quit.
Esc during play pauses and opens the pause menu (resume, save, settings, back
to the title screen, quit). Castles keep growing on the clock while paused,
just as when the game is closed.

Settings (fullscreen, vertical sync, shadows, ambient occlusion, 3D
resolution and interface size) apply at once and are kept in
`user://settings.cfg` by the `Settings` autoload.

## Castle economy

Your castle produces **wood, stone, food and gold** in real time, including
while the game is closed: when you start it again, the castle catches up on the
time that passed. The help panel on the world map shows your stock, storage
limit and production per hour.

### Castle screen

Press **C** or click **Your castle** on the world map to walk into your castle;
press C again or click **Map** to go back. Both screens stay loaded, so
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
- NPC castles open in the same screen read-only.

### Castles on the world map

**Your Castle** stands just south-east of Highford, with its name in gold.
Every castle on the map now has an economy. Click one to see who holds it,
its keep level, defence and income, then **Enter castle** (yours),
**Look inside** (an NPC lord's) or **Travel here**. Clicking towns, villages
and open ground still sends your party straight there.

- Your castle's map position is in `data/player.json`, so regenerating
  `settlements.json` doesn't lose it.
- NPC castles are run by `NpcBrain` under exactly the same rules as yours:
  same costs, build times, builders and storage. Whenever a builder is free it
  starts the most useful thing it can afford (the keep once nothing else can
  grow, a storehouse when the keep needs more room, the producer of its
  slowest resource, the wall, then the keep anyway).
- On a new game each NPC castle starts with 12 to 72 hours of building behind
  it, so lords are a little ahead of you. NPC castles keep building while the
  game is closed (up to a week is simulated decision by decision).

- **Buildings** are defined in `data/buildings.json`: keep, castle wall,
  woodcutter, quarry, farm, house (taxes in gold) and storehouse. Each has a
  level-1 cost, build time and output, and a growth factor per level
  (`value x growth^(level - 1)`), so balancing means changing a few numbers.
- **The keep sets the limits**: other buildings can go up to twice its level,
  it decides how many of each you may build, and it adds builders (one at
  first, more at keep levels 3 and 5). Builders are the only way to build
  faster; there is no premium currency and nothing to buy.
- **Storage** comes from the keep and storehouses and caps every resource.
- **Saving** is automatic every 30 seconds and on quit, to the slot you are
  playing (`saves/slot_N.json` in the game's user folder,
  `%APPDATA%\MedievalStrategy` on Windows). An old `savegame.json` from before
  save slots is moved into slot 1.
- `CastleState` runs one castle and is written so NPC castles can use exactly
  the same code later.

Run the economy tests with:

```
godot --headless --path . --script res://tests/test_economy.gd
```

## Recruitment

Build a **Barracks** (from the build menu) and click it to train soldiers.
Each unit costs gold and some food, wood or stone, takes real time to train and
then eats food every hour. Higher barracks levels unlock stronger units and
train a little faster.

| Unit | Barracks level | Cost | Time | Food/h | Attack | Defence |
|---|---|---|---|---|---|---|
| Spearman | 1 | 12 gold, 10 food | 20 s | 1 | 8 | 12 |
| Archer | 2 | 15 gold, 14 wood | 28 s | 1 | 12 | 6 |
| Swordsman | 3 | 28 gold, 8 stone, 10 food | 45 s | 1.5 | 16 | 15 |
| Horseman | 4 | 45 gold, 25 food | 70 s | 3 | 24 | 12 |

- Up to 5 batches of up to 50 soldiers queue up and train one after another,
  also while the game is closed. Cancelling a batch refunds 75% of what its
  untrained soldiers cost.
- The resource bar shows food **after** upkeep, so it can go negative. When
  the stores run dry, soldiers desert: each hour of food a soldier goes
  without costs you one soldier, until the farms can feed the rest.
- NPC lords build a barracks from keep level 2 and recruit from what they
  have to spare, up to 60 soldiers per keep level, never starving them.
- All unit numbers are in `data/units.json`.

### Your warband

Your party on the map is your castle's **warband**, and it starts at your
castle with 24 spearmen. Click **Warband** in the castle's top bar to send
soldiers from the garrison into the warband or call them back. That only works
while the warband stands at your castle, so march home to reinforce. The castle
keeps feeding its warband wherever it goes, and hungry warband soldiers desert
like any others.

Every lord's party is likewise the warband of one of their faction's castles
(`"home"` in `data/parties.json`). A lord visiting home tops the warband up to
40 + 20 per keep level from the garrison, best soldiers first, always leaving
half the garrison behind; a lord whose warband falls below 20 heads home.

### Battles

Click a lord's party on the map to see their warband, which faction they serve
and your chances against them, then press **Attack** to march on them. When two
warbands meet, `Battle` (`scripts/economy/battle.gd`) fights it out in rounds:
each soldier deals their attack, an enemy soldier falls for every point of
damage equal to their defence, and a side flees once it is down to 35% of its
soldiers. Spearmen hit horsemen hard, archers hit spearmen, and horsemen ride
down archers (`"bonus"` in `data/units.json`). The winner's castle plunders 3
gold for every enemy that fell. Your own battles end with a report; battles
between lords show up as a line of news at the bottom of the screen.

Which factions are at war when a game starts is listed under `"wars"` in
`data/factions.json` (Aldmere and Varnholt to start with); after that, wars come
and go (see Diplomacy). Lords of warring factions fight when they
meet, sometimes raid each other's towns, and a lord at war with you who spots
your warband comes after it if they think they will win. Your warband is safe
while it stands at your castle, and slipping into a town or village shakes off
a pursuer. A beaten lord goes home to recover. Attacking a lord, or besieging a castle,
of a faction you are at peace with asks you to declare war first.

### Sieges

Click a castle of another faction to see its walls, its garrison and your
chances, then press **Besiege**. Your warband marches to the walls and camps
there for 30 s plus 15 s per wall level (a countdown hangs over the castle),
then storms them: a `Battle` against the garrison, whose defence the wall
raises by up to 150% (half of that at wall defence 200). Walking away lifts
the siege, and so does losing a battle while camped.

A castle that falls changes hands with its buildings and stock
(`Economy.capture`): its banner, colours, label and parchment territory turn
yours, and you can build and recruit in it from the castle screen. Its lord
moves with their warband to their faction's nearest castle, or leaves the map
if there is none. Your main castle can never be captured; storming it sacks
30% of its stock instead.

Lords besiege too. Now and then a lord with at least 40 soldiers marches on
the nearest castle of a faction they are at war with (within 650 map units)
if they are at least 70% sure of storming it; that includes your castles. A
red warning at the top of the screen counts down to the assault on any castle
of yours, and attacking the besieger lifts the siege. A castle that has just
been stormed is left alone for 10 minutes. Your main castle is safe from
sieges until its keep reaches level 2 (newcomer's protection), so train a
garrison before you upgrade it.

## Diplomacy

You rule Aldmere: its lords follow your wars. `Diplomacy`
(`scripts/core/diplomacy.gd`, owned and saved by `Economy`) keeps the wars,
truces and a relation from -100 to 100 between every pair of factions.

- **Relations** wander over time, drifting back to how two factions usually get
  on (some are old rivals). Declaring war costs 40 with the victim and 5 with
  everyone else; peace gains 20.
- **AI factions** think every 30 seconds. A faction that dislikes another
  (below -30), isn't already fighting two wars and is at least 80% as strong
  may declare war. Wars last at least 20 minutes; after that, a faction that is
  losing, or tired of a long war, makes peace. Peace brings a 30 minute truce.
  Newcomer's protection also keeps new wars off you.
- **War score** follows each war: +5 for a won battle and 0.1 per enemy
  killed, +25 for taking a castle, +10 for sacking one.
- **Peace with you** is never made without you. An AI faction losing to you
  offers peace. One you propose peace to accepts if it is losing, if the war
  has dragged on or if it likes you, or else names a price in gold (10 gold
  per missing point); a faction that is clearly winning refuses.
- **Gifts** of gold improve relations, less per coin for big gifts, and at most
  30 points per faction per hour, so gold can't simply buy friendship.

New wars and peace treaties appear in the news line at the bottom of the
screen, and peace calls off sieges and chases between the two factions.

The **diplomacy screen** (K, or the Diplomacy button) lists every other faction
with your relation and your war or peace: how long the war has run and who is
winning, or how long a truce has left. From there you declare war (it asks
first), make peace (free if they offered it or are losing, otherwise for the
gold they ask, and impossible while they are clearly winning) and send gifts of
100 or 500 gold, each button showing the goodwill it would buy. Below are the
other factions' wars and the latest news.

## Project layout

```
data/        JSON: terrain config, factions, settlements, roads, parties, buildings, units, player
world/       heightmap, biome mask, rivers
scenes/      main.tscn -> world_map/world_map.tscn and castle/castle_view.tscn
scripts/
  core/      main (switches map and castle), GameData, EventBus and Economy autoloads, map style
  economy/   castle economy: building rules, castle state, NPC brain, battles
  castle/    castle screen: view, camera, placeholder building models
  terrain/   generator, terrain data and queries, terrain/water/river/tree layers
  world/     world map root, settlements, banners, roads, parchment overlay
  camera/    campaign camera
  ui/        world map HUD and panels (castle, party, battle report), castle HUD
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
- [x] Your castle and NPC castles on the world map
- [x] Barracks, training queue, food upkeep and desertion
- [x] Moving troops between your castle and your warband
- [x] Battles between warbands, with battle reports
- [x] Siege rules and capturing castles
- [x] Besieging castles from the map
- [x] Lords besiege castles, including yours
- [x] Main menu, pause menu and settings
- [x] Save slots
- [x] Diplomacy rules: relations, wars and peace between the factions
- [x] Diplomacy screen

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

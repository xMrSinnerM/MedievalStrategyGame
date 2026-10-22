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

### Look

Menus and panels share one look: dark oak boards with bronze rims, gold
titles in Cinzel and text in Alegreya Sans (both SIL Open Font License, in
`assets/fonts/` with their licences). `GameTheme` builds it in code and lays
it over Godot's default theme at start, so new buttons, sliders, progress
bars and tooltips pick it up on their own. Along the top of the castle screen
and the world map a resource bar shows each resource's icon, how much is
stored out of the storehouse limit, a bar filling as it nears the limit and
the gain an hour, then builders, defence and soldiers; hover a counter for
details. The icons are small SVG drawings in `Icons`, made at any size.

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
  it decides how many of each you may build, and it adds builders (two at
  first, a third from keep level 4). Builders are the only way to build
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
| Swordsman | 3 | 28 gold, 8 stone, 10 food | 45 s | 1 | 16 | 15 |
| Horseman | 4 | 45 gold, 25 food | 70 s | 1.5 | 24 | 12 |

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

### Siege waves

Every attack on a castle or a robber baron camp (sieges, sent attacks and
attacks on players online) is fought in waves over three walls, like Goodgame
Empire (`Battle.siege`, ported in `server/rules/battle.ts`):

- The defenders stand on the **left**, **front** and **right** walls, with a
  reserve in the **courtyard**: 25%, 35%, 25% and 15% of them.
- The attackers come in waves, each with soldiers for every wall. Without a
  choice the army goes in one wave, 30% left, 40% front and 30% right. A
  higher keep allows more waves: 2 from keep 2 and 3 from keep 4.
- Each wave fights each wall's defenders behind the wall. Attackers who lose
  on a wall go home. A broken wall lets the next waves walk straight through,
  and its last defenders fall back into the courtyard.
- Break at least one wall, then win the courtyard, where the defenders make
  their last stand around the keep (the wall's bonus times 1.5).

On the attack screen you plan the siege: a tab for every wave your keep
allows, and for each wave how many of each soldier go to the left, front and
right walls. **Auto** tries every number of waves you can send with eight ways
of spreading them over the walls, and picks the plan with the best odds (then
the fewest losses) against what it knows of the defence: a camp's garrison,
or what your spy last saw of a player's soldiers, walls and layout.

In the castle screen, **Defence** sets how the garrison mans each wall and
the courtyard: a slider per post in steps of 5%, the soldiers that puts there,
and a warning for an empty wall or courtyard. The four must add up to 100%
before you can save. Every castle keeps its own layout (offline, captured
castles too). Online it is stored on the server (`set_layout`), and a spy's
report on your castle shows it.

Battle reports say which walls broke and how the courtyard went, with a row
for each wall and the courtyard: broken in which wave, held, undefended or not
attacked, and who fell there.

## Balance

The pace is set so a castle takes **about a month** to build up fully for a
player who looks in a few times a day: the first upgrades take a minute or
two, the top ones most of a day (the keep's last level about 17 hours), and
the storage holds about a night's production. Playing nonstop is faster, but
not by much more than twice, because the long top upgrades wait on the
builders rather than on the player.

`tools/balance_sim.gd` plays a new castle forward through the game's own rules
and prints a Markdown report: the keep levels and their costs, robber baron
camps by level, when each keep level is reached, production, storage and
soldiers over time, and how a raiding player's attacks went. It runs two
players side by side, one who only builds and trains (`NpcBrain`) and one who
also attacks the camp that pays best:

```
godot --headless --path . --script res://tools/balance_sim.gd -- days=45 checkins=4 out=/tmp/balance.md
```

`checkins=N` makes both players look in N times a day between 8:00 and 23:00
(leave it out to have them decide every 10 minutes). With the current numbers:

| | Keep 2 | Keep 5 | Everything built |
|---|---|---|---|
| 4 visits a day | 2 days | 22 days | 35 days |
| Nonstop | 13 hours | 10 days | 17 days |

Robber baron camps are worth raiding: for a player who looks in 4 times a day
and sends their army out each time, loot is about a sixth of their income in
the middle of the game (days 7 to 21) and less later on, when their own
production has grown. Raiding doesn't build the castle faster (the top
upgrades wait on the builders), but it pays for a bigger army.

Spearmen and archers give the most fighting for what they cost to train;
swordsmen and horsemen give the most for the food they eat. Early on, when
resources are short, cheap soldiers pay; later, when food is what limits the
size of an army, the strong ones do.

Online, a castle can't attack one whose keep is more than one level below its
own (`attack_keep_gap` in `data/pvp.json`), so big castles fight castles of
their own size rather than farming small ones. To be sure of winning, an
attacker needs about one and a half times the defenders' soldiers, or twice as
many against a fully built wall.

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

## Robber barons

Robber baron camps are the game's main source of loot, as in Empire: Four
Kingdoms. Each camp starts at level 1, and every win against it counts towards
its next level: one win per level at first, two from level 10 and three from
level 20. A higher camp has a bigger garrison (14 soldiers at level 1, growing
16% a level, with swordsmen from level 4 and horsemen from level 8), a stronger
palisade and richer loot (1,320 resources at level 1, 15% more a level,
worth about an hour of your own production for the camps you can beat in the
middle of the game). Winners carry off up to 20 resources per surviving
soldier. A beaten camp rebuilds for 5 minutes plus 30
seconds per level before it can be attacked again; a camp that holds keeps its
level. All of these numbers live in `data/barons.json` (`BaronRules`), and each
camp's level is saved with your game (`BaronCamp`, `Economy.barons`).

Thirty camps are spread over the map from a fixed seed (`BaronPlacer`, settings
under `"camps"` in `data/barons.json`): on open ground, away from settlements
and from each other. The two nearest your castle start at level 1, and camps
start a level higher for every 170 map units further out (up to level 12).
Each shows a palisade, tents and a black banner, with its name and level, and
a countdown while it rebuilds.

Click a camp to see its level and wins towards the next, its garrison,
palisade and loot, the march time and your chances, then press **Prepare
attack**. The attack screen lets you plan which soldiers storm which wall in
each wave (or let **Auto** do it, see Siege waves) and shows, as you change it, your chances and the losses
to expect (from a dozen simulated battles), how much of the loot they can carry
and the march time. As in Empire: Four Kingdoms, the soldiers leave your main
castle's garrison and march on a timer (6 map units a second, at least 10
seconds each way), fight on arrival, and march home with the loot, which goes
into your storage. You see your armies on the map with their time left, a
battle report when they fight, and "Armies away" at the top of the screen.
Marches carry on while the game is closed and are settled when you load it.
Your warband's soldiers can join the garrison when it is home (the warband
panel).

## Quests and daily tasks

Press **J** (or the **Quests** button, or click the quest box under the
controls on the map and on the left of the castle screen) for the
quest screen. It works the same offline and online.

**The story.** Your steward, Bertram, walks you through 30 quests in five
chapters, from rebuilding a burned valley ("Ashes and Timber") to bringing
down the Black Baron, the robber lord behind every camp on the map ("The
Black Baron Falls"). One quest is open at a time: build or upgrade
something, train soldiers, beat robber barons, bring home loot, reach a
production, storage or total building level. Each reward (resources and
sometimes soldiers) arrives in full when you claim it, even past your
storage cap, and grows from a few hundred resources to 30,000 of each. The
quest box glows when a reward is waiting.

**Daily tasks.** Every day at 00:00 UTC you get three tasks, picked from:
finish building levels, spend resources, train soldiers, beat robber barons
and bring home loot (without a barracks only the first two). Targets and
rewards are set by your keep level when the day begins (rewards x1, x2, x5,
x12, x25 from keep 1 to 5), and count from what you had at the start of the
day. Finish all three to open the **Steward's Coffer**. Opening it on days in
a row makes it 25% richer each day, up to 2.5 times on the seventh day, which
also adds swordsmen; miss a day and the streak starts over.

The numbers live in `data/quests.json`. Progress is read from the castle
itself and from lifetime stats it now keeps (soldiers trained, resources
spent less refunds, barons beaten, loot brought home), so `QuestBook`
(`scripts/economy/quest_book.gd`) and the server's `server/rules/quests.ts`
give the same answers (checked by the server fixtures).

## Siege workshop

Build a **Siege Workshop** (3x3, wood 160, stone 120, gold 40) and click it
to build siege tools from a queue, like soldiers in the barracks. Each
workshop level builds faster (8% a level) and unlocks more tools:

| Tool | Side | Workshop | Cost | What it does, per tool at that wall |
|---|---|---|---|---|
| Ladder | attack | 1 | 60 wood | Takes 8% off the wall's bonus |
| Mantlet | attack | 3 | 60 wood, 20 gold | The defenders there deal 5% less (half at most) |
| Battering ram | attack | 5 | 200 wood, 60 stone, 60 gold | Takes 20% off the wall's bonus; front wall (the gate) only |
| Arrow slits | defence | 1 | 100 stone, 30 wood | The defenders there deal 5% more |
| Moat section | defence | 3 | 150 stone, 30 gold | The wall is 5% stronger |
| Boiling pitch | defence | 5 | 80 wood, 50 gold | The attackers there deal 5% less (half at most) |

Ladders and rams together can take a wall's whole bonus away, but never make
it weaker than no wall at all.

**Attacking.** The attack screen shows a row per attack tool in store, with
a number for each wall. Your keep decides how many tools fit on one wall
(2, 4, 6, 8, 10 from keep 1 to 5). Auto hands out your tools too: rams at
the gate, then ladders and mantlets to the walls with the most soldiers.
Tools are used up in the attack, won or lost. The odds count your tools and,
against a player, the defence tools your spy saw.

**Defending.** The Defence screen (in the castle) now has a row per defence
tool: post them on the left, front and right walls, up to 2, 4, 6, 8, 10 per
wall by wall level. They stay until their wall is broken in an attack, then
they are lost. Spies see them.

The numbers live in `data/units.json` (`tools`, `tool_slots`) and the
workshop in `data/buildings.json`. The rules are `Battle.wall_mods()` and
`Battle.check_tools()` (`scripts/economy/battle.gd`), the same as
`server/rules/battle.ts` (checked by the server fixtures).

## Commanders and gear

Press **H** (or the **Commanders** button on the map) for the commanders
screen. It works the same offline and online.

**Commanders** lead your attacks. You start with Sir Edric Vane; Dame Isolde
Marsh joins at keep level 3 and Sir Gareth Holt at keep 5. Pick one on the
attack screen (the first one at home is picked for you). A commander is away
until the army is home, earns xp from every fight (a camp's level for a win,
15 for beating a player, 1 for a loss) and rises up to level 10, each level
adding 2% to their army's attack at the walls and in the courtyard. Your
**castellan** stays home and leads your castle's defence.

**Gear.** Beaten robber barons drop gear: 30% of the time from a level 1
camp, up to 90% from level 31. Each piece is attack gear (for commanders) or
defence gear (for the castellan), for one of four slots (helmet, armour,
weapon, banner), in five rarities: common (one bonus of 2-4%), uncommon (one
of 4-7%), rare (two of 5-9%), epic (two of 8-12%) and legendary (three of
11-15%, with names like "Gatebreaker" or "Crown of the Black Baron").
Stronger camps drop rarer gear: legendaries only from level 20 up.

| Bonus | Side | What it does |
|---|---|---|
| attack at the walls / in the courtyard | attack | Your soldiers hit harder there |
| off the wall's bonus | attack | Like ladders: takes that share off the wall's bonus |
| loot carried | attack | The army carries that much more home |
| defence on the walls / in the courtyard | defence | Your defenders hit harder there |
| wall strength | defence | Like a moat: the wall is that much stronger |

Bonuses add up over the four slots, up to 60% each (50% for the wall ones,
100% for loot). Click gear in your bag (30 places) to give it to someone or
sell it for gold (40 to 1,500 by rarity); click worn gear to take it off. A
commander's gear can't change while they are away. When the bag is full, new
drops are lost. Spies see the castellan's bonuses.

The numbers live in `data/gear.json`. `GearRules`
(`scripts/economy/gear_rules.gd`) and the server's `server/rules/gear.ts`
give the same drops, bonuses and xp (checked by the server fixtures).

## Outpost: your second castle

Press **P** (or the **Outpost** button on the map). Once your keep reaches
level 3 you can found an outpost for 4,000 wood, 4,000 stone, 2,000 food and
2,000 gold, paid from your main castle. It goes on the free castle spot
nearest your home, and you pick the land it works:

| Region | Bonus |
|---|---|
| Timberland | +50% wood |
| Quarry Hills | +50% stone |
| Farmlands | +50% food |
| Trade Post | +50% gold |

The outpost is a castle of its own: click it on the map and **Enter
outpost** to build there. It has its own storage, builders and production,
and the region's bonus applies to everything it makes of that resource. It
can build woodcutters, quarries, farms, houses, storehouses, its wall and a
keep up to level 3, but no barracks or workshop, and it can't be attacked.

**Carts** carry resources between your two castles (the **Carts** button in
the outpost screen or on either castle's panel). One trip carries up to half
of the sending castle's storage (at least 500) and takes as long as an army
would to march the distance; you see the carts on the map. What doesn't fit
in the storage when they arrive is lost, so build storehouses.

Online, other players see your outpost on the map (and you theirs). The
numbers live in `data/outposts.json`; `OutpostRules`
(`scripts/economy/outpost_rules.gd`) and the server's
`server/rules/outposts.ts` follow the same rules (checked by the server
fixtures).

## Resource villages

36 villages lie across the map, each working one resource: wood, stone, food
or gold (a market village). Press **B** (or the **Villages** button) for the
ones you hold and the nearest others, or click one on the map. Villages near
the edge of the map are level 1 and get stronger towards the middle, up to
level 5; a higher level sends more and is guarded by more soldiers.

The local militia hold a village behind a palisade until someone beats them.
Attack it like a robber baron's camp (**Prepare attack**, with waves, a
commander and siege tools). Win and the village is yours, if your keep has
room: a level 2 keep holds 1 village, level 3 holds 2, level 4 holds 3 and
level 5 holds 4. Your army also carries home what the village had stored.

A village you hold sends its resource to your castle every hour (level 1 sends
70 wood, 70 food, 60 stone or 30 gold, and each level sends about half as much
again). What your castle hasn't taken yet waits in the village, up to 12
hours' worth, and whoever takes the village carries it off. You can give a
village up on its panel; the militia take it back.

Online, other players can take your villages. Send soldiers from your castle
to guard one (they fight behind its palisade, and you can bring them home),
and a village that has just changed hands is at peace for 2 hours. Villages of
your alliance can't be attacked. The numbers live in `data/villages.json`;
`VillageRules` (`scripts/economy/village_rules.gd`) and the server's
`server/rules/villages.ts` follow the same rules (checked by the server
fixtures). Where the villages stand is in `server/world/world.json`, written by
`scripts/tools/export_server_world.gd`.

## Multiplayer (in progress)

The multiplayer server runs on Supabase. It uses the same rules as the game,
ported to TypeScript in `server/rules/`, and decides everything itself on
server time, so changing your computer's clock or the save file changes
nothing online. A test replays random castle orders, battles and robber baron
attacks from the game and checks the server gets exactly the same results;
see `server/README.md`.

The server is live on Supabase: players sign up with email and password, and
every order (building, training, attacking a robber baron) goes through the
`game` function, which runs the player's castle up to the server's clock
first.

To play online, pick **Play online** on the main menu, then create an
account or sign in (email and password) and name your castle. Online you
have your castle on your own spot of the map, the other players' castles
around you, and the robber baron camps. Click another player's castle to
send a spy or an attack; new players are protected from attacks for their
first five days (or until their keep reaches level 3), and nobody can
attack a castle whose keep is more than one level below their own. Press L for the leaderboard: the mightiest castles and
the robber barons they have beaten. Your castle keeps building and
training while the game is closed, and nothing is saved on your computer
except that you're signed in. The warband, lords and diplomacy are single
player only for now. Single player works offline exactly as before.

### Alliances

Press G (or the Alliance button) online to open the alliance screen. Any
player with keep level 2 can found an alliance for 300 gold, with a name and
a tag of 2 to 4 letters; there's nothing to buy. Open alliances let anyone
join; closed ones take requests, which the leader and officers answer. They
can also invite players by name. The leader can make members officers, hand
over the leadership, remove members, change the settings or disband the
alliance; if the leader leaves, an officer takes over. Alliances hold up to
30 players (`data/alliances.json`).

Tags show on the map and the leaderboard, and your allies' castles are
labelled in green. You can't spy on or attack a member of your own alliance.

### Chat

Online, the chat box sits in the bottom left corner of the map. Press Enter
to open it and type, Enter again to send, and Esc to get back to the game.
The World tab is for everyone; the Alliance tab only for your alliance, and
it shows the alliance's recent talk when you join. Messages are up to 200
characters, one every 2 seconds, and are kept for three days. While you type,
the keys don't move the camera.

### Helping allies

Click a member of your alliance on the map to send them resources or
defenders. A cart carries up to 500 resources per level of your keep and
takes as long as a march; what their storage can't hold is lost. Defenders
stand in their castle for 8 hours and fight beside their garrison if it is
attacked, then walk home. You can call them back sooner from the same panel.
Allied defenders in your own castle show when you click it, and a battle
report says when they fought for you. Helping costs only what you send, so
it can't be bought.

### Timed events

Online, a banner at the bottom of the map shows the event that's on and how
long it lasts, or the next one. Events follow a weekly calendar in UTC, the
same for everyone (`data/events.json`). The first is the Plunder Weekend,
Friday 18:00 to Monday 00:00 UTC: robber barons drop 50% more loot, and the
camp and attack panels show the bonus.

The Baron Invasion runs from Wednesday 12:00 to Friday 12:00 UTC. Three
invader camps (red banners) appear near every castle, the first at level 1
plus 2 per keep level above 1 and each next one a level higher. Every win
raises an invader camp a level and gives 10 event points per level it had,
and a beaten camp is back after two minutes. The banner, the camp panel and
the battle report show your points. The camps leave when the event ends.

The event screen (V, or the Events button) shows the week's events, the
invasion's reward tiers and the players with the most points. Reach a tier's
points to claim its resources or soldiers, in order, until the next invasion
starts: 50, 150, 300, 600, 1000 and 2000 points. Rewards are earned only by
playing; nothing can be bought. Resources go into your storage, and what
doesn't fit is lost.

### Owner tools

The game owner's account gets an Owner button (O) on the world map. Its panel
starts or stops any event right away, for as many hours as you choose, and
gives resources and soldiers to one player or to everyone (gifts may go over
the storage limit). Players see a message when a gift arrives. The server
checks every order and writes it to an admin log, which the panel shows.
Other players never see the panel, and no account can make itself the owner
from the game: owners are added by hand in the database (see
`server/README.md`).

## Project layout

```
data/        JSON: terrain config, factions, settlements, roads, parties, buildings, units, player
world/       heightmap, biome mask, rivers
assets/      fonts (SIL OFL)
scenes/      main.tscn -> world_map/world_map.tscn and castle/castle_view.tscn
scripts/
  core/      main (switches map and castle), GameData, EventBus and Economy autoloads, map style
  economy/   castle economy: building rules, castle state, NPC brain, battles
  castle/    castle screen: view, camera, placeholder building models
  terrain/   generator, terrain data and queries, terrain/water/river/tree layers
  world/     world map root, settlements, banners, roads, parchment overlay
  camera/    campaign camera
  ui/        world map HUD and panels (castle, party, battle report), castle HUD, theme, icons, resource bar
  tools/     command-line tools (world generator, settlements, roads)
shaders/     terrain, water, river, tree, prop, flag, route, parchment, castle ground (+ shared fog include)
tests/       headless tests (economy), server fixture writer
server/      multiplayer server: game rules in TypeScript, tests, world export (see server/README.md)
supabase/    database migrations and the game server (Edge Function)
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
- [x] Robber baron rules: levels, garrisons, loot, rebuilding
- [x] Robber baron camps on the map and sent attacks
- [x] Attack screen: choose your soldiers
- [x] Server rules in TypeScript, checked against the game
- [x] Server on Supabase: database, accounts, game server
- [x] Play online from the game
- [x] Alliances
- [x] Chat (world and alliance)
- [x] Helping allies: sending resources and soldiers
- [x] Timed events: weekend loot bonus, baron invasions, event rewards and leaderboard
- [x] Owner tools: start and stop events, give players resources and soldiers
- [x] Siege waves: battle rules (walls and courtyard)
- [x] Siege waves: choose your waves on the attack screen
- [x] Siege waves: set your defenders on the walls
- [x] Quests and daily tasks
- [x] Siege workshop: attack and defence tools
- [x] Commanders and gear

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
- Fonts (SIL OFL): IM Fell English; Cinzel and Alegreya Sans are already in `assets/fonts/`

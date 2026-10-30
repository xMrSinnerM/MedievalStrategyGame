# Server

The multiplayer server runs on Supabase. This folder holds its game rules,
ported from the game's GDScript to TypeScript so the server can decide
everything itself: production, building, training, battles and robber baron
attacks, all on server time.

- `rules/`: the rules. They read the same `data/*.json` files as the game.
  - `building_rules.ts`, `castle_state.ts`: the castle economy (from `scripts/economy/building_rules.gd`, `castle_state.gd`).
  - `battle.ts`, `rng.ts`: fights, with Godot's random number generator so a seed gives the same fight.
  - `baron_rules.ts`, `baron_camp.ts`: robber baron camps.
  - `marches.ts`: armies sent against camps (from the march code in `scripts/core/economy.gd`).
- `tests/`: checks that the TypeScript rules give exactly the game's results.

## Tests

Needs Node 22.18 or newer (it runs TypeScript directly):

```
node --test server/tests/*.test.ts
```

`tests/fixtures.json` holds random castle orders, battles and camp attacks
run through the game's own rules. After changing a rule or a number in
`data/`, change the TypeScript the same way and write new fixtures:

```
godot --headless --path . --script res://tests/dump_server_fixtures.gd
```

## The game server on Supabase

- `supabase/migrations/`: the database. `players` holds each player's castle,
  robber baron camps and marches as JSON, `reports` their battle reports,
  `raids` the armies players send against each other, `alliances` and
  `alliance_pending` (invitations and requests to join) the alliances,
  `chat_messages` the world and alliance chat, and `aid` the carts and
  defenders sent between allies.
  Players can read their own rows only; nobody but the game server can write.
- `supabase/functions/game/`: the game server, one Edge Function. `index.ts`
  checks who is signed in, loads their row, and `game.ts` runs their world up
  to the server's clock and carries out the order. Orders: `join`, `state`,
  `place`, `upgrade`, `cancel`, `move`, `recruit`, `cancel_training`, `attack`,
  `attack_player`, `spy`, `world` for the other players' castles and
  `leaderboard`, and the alliance orders (see the top of `index.ts`).
  `alliances.ts` holds the alliance rules behind a store, and
  `alliance_store.ts` keeps them in the database.
- `world/world.json`: the robber baron camps and the spots where players'
  castles can stand, written by `scripts/tools/export_server_world.gd`
  because the server can't read the terrain.

Players sign up with email and password (Supabase Auth). Each new player gets
a free spot on the map at random, and the same camps as everyone, with their
own camp levels: camps near their castle start at level 1. Other players see
only your name, spot and keep level, unless they send a spy.

Players can attack each other with the same battle rules as camps: the army
fights the defender's garrison behind their wall, and a win carries off up to
a quarter of each resource, as much as the survivors can carry. New players
are protected for three days or until their keep reaches level 3, and lose
the protection early if they attack someone (`data/pvp.json`). The battle is
fought by whichever side's next request comes after the army arrives.

The leaderboard ranks castles by might (10 per building level and 1 per
soldier at home, in `data/pvp.json`) and shows the robber baron camps each
player has beaten. The server works both out each time it saves a castle.

Alliances cost gold to found (`found_alliance`, paid from the castle like any
other order) and need keep level 2 (`data/alliances.json`). The other
alliance orders (`alliance`, `join_alliance`, `invite`, `answer_request`,
`set_role`, `kick`, `leave_alliance`, `disband_alliance` and the rest) answer
with the alliance screen's view. The map and the leaderboard carry each
player's tag, and the server refuses spies and attacks on your own alliance.

Chat (`chat.ts`, kept in the database by `chat_store.ts`) has a world channel
and one per alliance. `chat` returns the messages newer than `after` that you
may read (the newest 50 at most), and `chat_send` sends one to `world` or
`alliance` first. Messages are cleaned of line breaks and control
characters, are at most 200 characters, need 2 seconds between them, and
are deleted after three days.

Allies can help each other (`aid.ts`, rows of the `aid` table).
`send_resources` loads a cart with up to 500 resources per keep level of the
sender (`data/aid.json`); it takes as long as a march and unloads into the
ally's storage when it arrives, and whatever their storage can't hold is lost.
`send_defenders` sends soldiers to stand in the ally's castle for 8 hours: if
the castle is attacked meanwhile they fight beside its garrison, losses are
shared in proportion, and spies see them too. Then they march home, or sooner
with `recall_defenders`. Both sides get a report. Only members of the same
alliance can help each other.

Timed events (`server/rules/events.ts`) follow a weekly calendar in
`data/events.json`, in UTC. Whether one is on is worked out from the time, so
nothing runs on a timer: a battle with a camp uses the bonus of the events on
at the moment it is fought. Every answer with your castle carries `events`,
the events on now and the next ones.

A Baron Invasion (`supabase/functions/game/invasion.ts`) adds invader camps
to the player's own camp list the first time they play while it runs, on
places around their castle that `world/world.json` lists for each spot
(`invasion_spots`), and starts their event points again from 0. Invader camps
are ordinary camps with an `event` field: they rise a level with every win,
rebuild quickly, and each win's report carries the event points it earned,
which go to the `event_points` column (with `event_key`, the invasion's
start). When the invasion is over, its camps leave once no army is marching
to or from them. New castles are placed on spots with room for every
invader camp first.

`claim_reward` gives the invasion's next reward tier (`rewards` in
`data/events.json`) when the player has its points; `event_claimed` counts
the tiers taken. Points count for the invasion on now, or the last one until
the next starts. `event_board` lists the players with the most points in
that invasion and the asking player's rank.

The Ember Horde (`supabase/functions/game/horde.ts`, `horde` in
`data/events.json`, its soldiers in `data/horde.json`) works the same way
with its own columns: when a horde run has begun since the player last
played, `hordeArrives()` puts its camps (with `horde`, the run's start, and
`until`, its end) on the same places and starts `horde_points` and `horde`
({trophies, bought, ranked}) again, with `horde_key` the run's start. A win
before `until` gives horde points and war trophies. `buy_horde` sells a
Trophy Market item for trophies, `stock` times per run, while that run is
the last one; `claim_horde_prize` gives the ranked prize once the run is
over, by the player's place among that run's players (`hordeRank()` in
index.ts, ties share a place). `horde_board` lists the most horde points,
the asking player's rank and the prize it earns. Migration
`20261026120000_ember_horde.sql` adds the columns.

Alliance wars (`supabase/functions/game/wars.ts`, `data/wars.json`) run in
weekly seasons (Monday 00:00 UTC to the next). Alliances win war points with
the capitals, as rows of `war_points` (season, alliance, capital, kind,
points): every request first gives each capital's holder's alliance its
`hold` points up to the start of the hour (`scoreCapitals()` in index.ts;
`villages.scored_at` is up to when, moved only by the request that counts
it), taking a capital gives `capture` points once per capital, alliance and
season, and holding one against another player gives `defence` points for
the attackers who fell. The view `war_standings` adds them up per season and
alliance. `war_board` answers with this season's and the last season's
standings, who holds each capital, the player's alliance and the prize they
can claim; `claim_war_prize` gives every member of a ranked alliance its
prize for the last season once (`players.war_claimed`), if they were in the
alliance before that season ended. Migration
`20261029120000_alliance_wars.sql` adds the table, view and columns. The
local server's `WAR_DAYS` makes seasons shorter for testing.

Quests (`server/rules/quests.ts`, `data/quests.json`) live in the castle's
own JSON (`quests`, with lifetime counts in `stats`), so they need no column
of their own. Every request starts a new day's daily tasks once the UTC day
turns, and `claim_quest` gives the story quest's, a daily task's or the
coffer's reward when it is done.

The Royal Gift (`server/rules/login.ts`, `data/login.json`) is kept in the
castle's JSON as `login` (the last UTC day it was taken, days in a row and
days in all); `claim_login` gives today's gift once a day.

Seasons (`server/rules/seasons.ts`, `data/seasons.json`) are kept in the
castle's JSON as `season` (the month counted, the stats it counts from, track
rewards claimed, last month's renown and season titles won). Every save also
writes `season_key`, `season_points`, `last_season_key` and
`last_season_points` columns (migration `20261031120000_seasons.sql`) so the
ranking can be read without opening castles. Orders: `claim_season` (the next
track reward), `claim_season_prize` (last season's prizes, by your place and
your alliance's, worked out from those columns) and `season_board`.

Achievements (`server/rules/achievements.ts`, `data/achievements.json`) live
in the castle's JSON as well (`achievements`: tiers earned, tiers claimed and
the title shown). Every request notes the tiers reached, before and after its
order; `claim_achievement` gives an achievement's next earned reward and
`set_title` shows an earned title ("id:tier", or "" for none). `world` and
`leaderboard` list each player's `title` (read from the castle JSON). The
castle's `stats` count battles won against players' castles (`pvp_won`, when
the army is home, from the `won` column of `raids`, migration
`20261026150000_raid_won.sql`) and attacks held off (`pvp_held`).

Siege tools are in the castle's JSON too (`tools` in store, `crafting`, and
`defence_tools` posted on the walls). Orders: `craft` and `cancel_crafting`
for the workshop, `set_tools` for defence tools; `attack` and
`attack_player` take `tools` ({wall: {tool: count}}) and use them up. A raid
keeps its tools in the `tools` column of `raids`
(`supabase/migrations/20261020120000_raid_tools.sql`), and a spy report
shows the defender's `tools`.

Commanders and gear (`server/rules/gear.ts`, `data/gear.json`) are in the
castle's JSON as `armoury` (commanders, the castellan's gear, the bag).
Orders: `equip`, `unequip` and `sell_gear`; `attack` and `attack_player`
take `commander` (an id). A raid keeps its commander, with their bonuses and
then the xp earned, in the `lead` column of `raids`
(`supabase/migrations/20261021120000_raid_lead.sql`); the xp is given when
the army is home. A spy report shows the defender's `castellan` bonuses.

A player's outpost (`server/rules/outposts.ts`, `data/outposts.json`) is the
`outpost` column of `players` (`supabase/migrations/20261022120000_outpost.sql`):
its name, region, spot, castle state and the carts on the road. Orders:
`found_outpost` (`region`), `send_carts` (`from`: "home" or "outpost",
`resources`), and `place`, `upgrade`, `cancel` and `move` with
`"castle": "outpost"`. The server picks the spot (the free one nearest your
home, counting other players' homes and outposts), and `world` lists each
player's `outpost`.

Resource villages (`server/rules/villages.ts`, `data/villages.json`, placed in
`server/world/world.json`) are rows of `villages`
(`supabase/migrations/20261024120000_villages.sql`): the owner, the guards
stationed there, when it changed hands (its peace runs from then) and up to
when its yield has been paid. The server adds the rows the first time it needs
them; a village without an owner is held by the militia. Armies sent to a
village are `raids` rows with `village` and `mission` ("attack", "station" or
"return") set and are resolved on any request once they arrive. Orders:
`attack_village` (`village`, `army`, `waves`, `tools`, `commander`), `station`
(`village`, `army`), `recall_guard` and `abandon_village` (`village`). Every
request first pays each of your villages' yield into your castle, and `view`
lists `villages` with their holder and alliance tag.

Capitals (the towns, `data/capitals.json`, listed under `capitals` in
`server/world/world.json`) are rows of the same `villages` table, attacked
and guarded with the same orders by their town id. `rulesFor()` picks
`CapitalRules` for them: a stronger guard, a keep of level 4, one capital a
player and three an alliance. Every request sets your castle's `boost` from
the capitals your alliance holds (or you alone) and their guild halls, so
all its members produce more. `build_capital` (`village`, `building`) starts
the next level of a town building in your capital: `act()` checks it and
pays from your castle, then `index.ts` saves it in the capital's `buildings`
and `building` columns if the row is unchanged since (and refunds the castle
if it isn't). A building under way counts once its `finish` has passed, with
no write needed; `capture()` keeps the buildings and drops one still going up.

Fortresses (the old kingdoms' castles, `data/fortresses.json`, listed under
`fortresses` in `server/world/world.json`) are camps in each player's
`camps` with `fortress` set: `BaronRules.forCamp()` gives them the fortress
numbers. `act()` adds any a player doesn't have yet, at level 1. They are
attacked with `attack` like any camp.

The game owner's tools (`supabase/functions/game/admin.ts`) work only for
accounts in the `admins` table, which the game can never change. Add one in
the SQL editor:

```
insert into public.admins (user_id) select id from auth.users where email = 'owner@example.com';
```

`admin` returns the owner's panel (or `is_admin: false` for everyone else),
`admin_start_event` and `admin_stop_event` change the calendar through rows in
`event_overrides` (an extra run of an event, or a scheduled run that ends
early), and `admin_give` adds resources and soldiers to one castle or to all
(`"target": "*"`) and leaves each player a `gift` report. Every one of these
is written to `admin_log`. With the local server, `ADMINS=email,...` names the
owner accounts.

To deploy changes with the Supabase CLI, from the repository root:

```
supabase link --project-ref acmjrnkgjiggyazarcwx
supabase db push
supabase functions deploy game
```

## Trying the game against a local server

`dev/local_server.ts` is a stand-in for Supabase on your computer: accounts
and players are kept in memory, and orders go through the real `game.ts`.

```
node server/dev/local_server.ts
godot --path . -- --online-url=http://127.0.0.1:54321
```

Set `START_TROOPS='{"spearman":60}'` to give new castles soldiers, so you can
attack a camp straight away. `START_RESOURCES='{"gold":800}'` and
`START_KEEP=2` do the same for resources and the keep's level, for trying
alliances.

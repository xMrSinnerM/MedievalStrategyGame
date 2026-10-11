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
  `raids` the armies players send against each other.
  Players can read their own rows only; nobody but the game server can write.
- `supabase/functions/game/`: the game server, one Edge Function. `index.ts`
  checks who is signed in, loads their row, and `game.ts` runs their world up
  to the server's clock and carries out the order. Orders: `join`, `state`,
  `place`, `upgrade`, `cancel`, `move`, `recruit`, `cancel_training`, `attack`,
  `attack_player`, `spy`, and `world` for the other players' castles (see the
  top of `index.ts`).
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
attack a camp straight away.

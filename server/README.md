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
  robber baron camps and marches as JSON, `reports` their battle reports.
  Players can read their own rows only; nobody but the game server can write.
- `supabase/functions/game/`: the game server, one Edge Function. `index.ts`
  checks who is signed in, loads their row, and `game.ts` runs their world up
  to the server's clock and carries out the order. Orders: `join`, `state`,
  `place`, `upgrade`, `cancel`, `move`, `recruit`, `cancel_training`, `attack`
  (see the top of `index.ts`).
- `world/world.json`: where the castle stands and the robber baron camps,
  written by `scripts/tools/export_server_world.gd` because the server can't
  read the terrain.

Players sign up with email and password (Supabase Auth). Until Phase 8 every
player gets the same spot on the map and the same camps, each with their own
camp levels.

To deploy changes with the Supabase CLI, from the repository root:

```
supabase link --project-ref acmjrnkgjiggyazarcwx
supabase db push
supabase functions deploy game
```

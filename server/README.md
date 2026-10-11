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

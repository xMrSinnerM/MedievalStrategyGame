// Weather on the map (server/rules/weather.ts): drifting rain and storm
// cells, the same as the game's, that slow the marches setting off through them.
//   node --test server/tests/*.test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { makeRules } from "../rules/load.ts";
import { activeCells, cellCentre, marchSlow, type WeatherRules } from "../rules/weather.ts";
import { act, newPlayer, type World } from "../../supabase/functions/game/game.ts";

const root = new URL("../../", import.meta.url);
const json = (path: string) => JSON.parse(readFileSync(new URL(path, root), "utf8"));
const rules = makeRules(json("data/buildings.json"), json("data/units.json"), json("data/barons.json"), json("data/gear.json"));
const weather: WeatherRules = json("data/weather.json");
const world: World = json("server/world/world.json");
const T = 1_800_000_000;

// From scripts/economy/weather_rules.gd at T: [id, kind, x, z, dx, dz, radius, start].
const GAME_CELLS = [["w0-166666", "storm", 925, 1117, -93, 123, 194, 1799992800.0], ["w1-166666", "clear", 295, 1664, -185, -104, 250, 1799991000.0], ["w2-166667", "storm", 1114, 402, 197, -335, 286, 1800000000.0], ["w3-166667", "clear", 1550, 807, 242, -224, 269, 1799998200.0], ["w4-166667", "clear", 890, 385, 301, -297, 206, 1799996400.0], ["w5-166667", "clear", 998, 1418, -360, -90, 238, 1799994600.0]];
// Routes [from, to, setting off at, how much slower]: the game's march_slow().
const GAME_ROUTES: [[number, number], [number, number], number, number][] = [[[100, 100], [100, 100], 1800000000.0, 1.0], [[237, 351], [489, 273], 1800001500.0, 1.0], [[374, 602], [878, 446], 1800003000.0, 1.0], [[511, 853], [1267, 619], 1800004500.0, 1.0], [[648, 1104], [1656, 792], 1800006000.0, 1.1], [[785, 1355], [245, 965], 1800007500.0, 1.0], [[922, 1606], [634, 1138], 1800009000.0, 1.0], [[1059, 1857], [1023, 1311], 1800010500.0, 1.0], [[1196, 308], [1412, 1484], 1800012000.0, 1.1], [[1333, 559], [1801, 1657], 1800013500.0, 1.3], [[1470, 810], [390, 1830], 1800015000.0, 1.1], [[1607, 1061], [779, 203], 1800016500.0, 1.3], [[1744, 1312], [1168, 376], 1800018000.0, 1.0], [[1881, 1563], [1557, 549], 1800019500.0, 1.0], [[218, 1814], [146, 722], 1800021000.0, 1.1], [[355, 265], [535, 895], 1800022500.0, 1.1], [[492, 516], [924, 1068], 1800024000.0, 1.0], [[629, 767], [1313, 1241], 1800025500.0, 1.0], [[766, 1018], [1702, 1414], 1800027000.0, 1.0], [[903, 1269], [291, 1587], 1800028500.0, 1.0], [[1040, 1520], [680, 1760], 1800030000.0, 1.0], [[1177, 1771], [1069, 133], 1800031500.0, 1.1], [[1314, 222], [1458, 306], 1800033000.0, 1.0], [[1451, 473], [1847, 479], 1800034500.0, 1.0], [[1588, 724], [436, 652], 1800036000.0, 1.0], [[1725, 975], [825, 825], 1800037500.0, 1.1], [[1862, 1226], [1214, 998], 1800039000.0, 1.3], [[199, 1477], [1603, 1171], 1800040500.0, 1.3], [[336, 1728], [192, 1344], 1800042000.0, 1.0], [[473, 179], [581, 1517], 1800043500.0, 1.3], [[610, 430], [970, 1690], 1800045000.0, 1.3], [[747, 681], [1359, 1863], 1800046500.0, 1.1], [[884, 932], [1748, 236], 1800048000.0, 1.0], [[1021, 1183], [337, 409], 1800049500.0, 1.1], [[1158, 1434], [726, 582], 1800051000.0, 1.1], [[1295, 1685], [1115, 755], 1800052500.0, 1.0], [[1432, 136], [1504, 928], 1800054000.0, 1.1], [[1569, 387], [1893, 1101], 1800055500.0, 1.1], [[1706, 638], [482, 1274], 1800057000.0, 1.1], [[1843, 889], [871, 1447], 1800058500.0, 1.0]];

test("the same weather is on the map as in the game", () => {
  assert.deepEqual(activeCells(weather, T).map((c) => [c.id, c.kind, c.x, c.z, c.dx, c.dz, c.radius, c.start]), GAME_CELLS);
});

test("marches through rain and storms are slowed as in the game", () => {
  const seen = new Set<number>();
  for (const [from, to, t, slow] of GAME_ROUTES) {
    assert.ok(Math.abs(marchSlow(weather, from, to, t) - slow) < 1e-6, `${from} -> ${to} at ${t}`);
    seen.add(slow);
  }
  assert.ok(seen.size >= 3, "clear, rain and storm all come up");
  assert.equal(marchSlow(undefined, [0, 0], [100, 100], T), 1);
});

test("cells drift across their window", () => {
  const c = activeCells(weather, T)[0];
  assert.deepEqual(cellCentre(weather, c, c.start), [c.x, c.z]);
  assert.deepEqual(cellCentre(weather, c, c.end), [c.x + c.dx, c.z + c.dz]);
});

test("a storm on the way slows an attack on a player", () => {
  const storm = activeCells(weather, T).find((c) => c.kind === "storm")!;
  const [cx, cz] = cellCentre(weather, storm, T);
  const p = newPlayer(rules, world, "Lord", T);
  p.home_x = cx - 400;
  p.home_y = cz;
  p.castle.troops = { swordsman: 20 };
  const target = { name: "Other", home: [cx + 400, cz] as [number, number], level: 1, ally: false, protected: false };
  const clear = act(rules, p, { action: "attack_player", target: "Other", army: { swordsman: 5 } }, T, { target } as never);
  const stormy = act(rules, p, { action: "attack_player", target: "Other", army: { swordsman: 5 } }, T, { target, weather } as never);
  assert.equal(clear.error, "");
  assert.equal(stormy.error, "");
  const a = clear.raid!;
  const b = stormy.raid!;
  assert.ok(Math.abs((b.arrive - T) / (a.arrive - T) - 1.3) < 1e-9, `${a.arrive} vs ${b.arrive}`);
});

// Gear and gems at the market, for Marks (supabase/functions/game/market.ts
// and the post_offer / buy_offer orders in game.ts).
//   node --test server/tests/*.test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { makeRules } from "../rules/load.ts";
import type { Item } from "../rules/gear.ts";
import { act, newPlayer, type PvpRules, type World } from "../../supabase/functions/game/game.ts";
import { goingRates, itemPriceRange, type MarketRules, type Offer } from "../../supabase/functions/game/market.ts";

const root = new URL("../../", import.meta.url);
const json = (path: string) => JSON.parse(readFileSync(new URL(path, root), "utf8"));
const rules = makeRules(json("data/buildings.json"), json("data/units.json"), json("data/barons.json"), json("data/gear.json"));
const world: World = json("server/world/world.json");
const pvp: PvpRules = json("data/pvp.json");
const marketRules: MarketRules = json("data/market.json");
const T0 = 1_000_000;

function sword(id: number): Item {
  return { id, slot: "weapon", side: "attack", rarity: "rare", name: "Runed Longsword", stats: { wall_attack: 8 }, gems: ["ruby:2"] };
}

function player(name: string, keep = 2) {
  const p = newPlayer(rules, world, name, T0, world.spots[1], pvp);
  p.castle.buildings.find((b) => b.type === "keep")!.level = keep;
  p.castle.armoury.bag = [sword(1)];
  p.castle.armoury.next_item = 2;
  p.castle.armoury.gems = { "ruby:2": 5 };
  p.castle.armoury.marks = 300;
  return p;
}

const post = (p: ReturnType<typeof player>, req: Record<string, unknown>, open = 0) =>
  act(rules, p, { action: "post_offer", want: "marks", ...req }, T0, { market: { rules: marketRules, open } });

test("price ranges", () => {
  const r = marketRules.items!;
  assert.deepEqual(itemPriceRange(r, rules.gear, "gear:rare", 1), r.gear_price.rare);
  assert.deepEqual(itemPriceRange(r, rules.gear, "ruby:2", 3), [r.gem_price[1][0] * 3, r.gem_price[1][1] * 3]);
  assert.equal(itemPriceRange(r, rules.gear, "glass:1", 1), undefined);
});

test("putting gear and gems up for Marks", () => {
  const p = player("Ann");
  const [lo, hi] = marketRules.items!.gear_price.rare;
  assert.equal(post(player("Ann", 1), { give: "gear", item: 1, want_amount: lo }).error,
    `The market opens at keep level ${marketRules.unlock_keep}.`);
  assert.equal(post(p, { give: "gear", item: 1, want: "stone", want_amount: lo }).error, "Gear and gems sell for Marks.");
  assert.equal(post(p, { give: "gear", item: 9, want_amount: lo }).error, "There's no such item in your bag.");
  assert.equal(post(p, { give: "gear", item: 1, want_amount: hi + 1 }).error, `Ask between ${lo} and ${hi} Marks for it.`);
  assert.equal(post(p, { give: "gear", item: 1, want_amount: lo }, marketRules.items!.max_offers).error,
    `You can have at most ${marketRules.items!.max_offers} gear and gem offers up at once.`);
  let out = post(p, { give: "gear", item: 1, want_amount: hi });
  assert.equal(out.error, "");
  assert.deepEqual(out.state.castle.armoury.bag, [], "the sword left the bag");
  assert.deepEqual(out.offer, { seller_name: "Ann", give: "gear:rare", give_amount: 1, item: sword(1), want: "marks", want_amount: hi,
    proceeds: hi - Math.ceil(hi * marketRules.fee), posted: T0, expires: T0 + marketRules.offer_hours * 3600 });
  assert.equal(post(p, { give: "ruby:2", give_amount: 6, want_amount: 30 }).error, "You have only 5 of those gems.");
  assert.equal(post(p, { give: "ruby:2", give_amount: 11, want_amount: 30 }).error, `One offer sells at most ${marketRules.items!.gem_lot} gems.`);
  assert.equal(post(p, { give: "ruby:9", give_amount: 1, want_amount: 3 }).error, "Choose what to sell.");
  out = post(p, { give: "ruby:2", give_amount: 3, want_amount: 30 });
  assert.equal(out.error, "");
  assert.deepEqual(out.state.castle.armoury.gems, { "ruby:2": 2 });
  assert.equal(out.offer?.give, "ruby:2");
  assert.equal(out.offer?.item, null);
});

test("buying gear and gems for Marks", () => {
  const offer: Offer = { id: 7, seller_name: "Ann", give: "gear:rare", give_amount: 1, item: sword(1), want: "marks", want_amount: 120,
    proceeds: 114, posted: T0, expires: T0 + 3600 };
  const buy = (p: ReturnType<typeof player>, o: Offer) =>
    act(rules, p, { action: "buy_offer", id: o.id }, T0 + 10, { market: { rules: marketRules, offer: o } });
  const bob = player("Bob");
  assert.equal(buy({ ...bob, name: "Ann" }, offer).error, "That's your own offer.");
  assert.equal(buy(bob, { ...offer, want_amount: 301 }).error, "You don't have enough Marks.");
  const full = player("Bob");
  full.castle.armoury.bag = Array.from({ length: rules.gear.bagSize }, (_, i) => sword(i + 1));
  assert.equal(buy(full, offer).error, "Your gear bag is full.");
  let out = buy(bob, offer);
  assert.equal(out.error, "");
  assert.equal(out.state.castle.armoury.marks, 180);
  assert.deepEqual(out.state.castle.armoury.bag.map((x) => [x.id, x.name, x.gems]), [[1, "Runed Longsword", ["ruby:2"]],
    [2, "Runed Longsword", ["ruby:2"]]], "it gets a new id in the buyer's bag, gems and all");
  assert.equal(out.state.castle.armoury.next_item, 3);
  assert.equal(out.marketReports?.[0].item_name, "Runed Longsword");
  out = buy(bob, { ...offer, give: "ruby:2", give_amount: 3, item: null, want_amount: 30 });
  assert.equal(out.error, "");
  assert.deepEqual(out.state.castle.armoury.gems, { "ruby:2": 8 });
});

test("the seller gets Marks; unsold gear and gems come home", () => {
  const p = player("Ann");
  p.castle.armoury.bag = [];
  const out = act(rules, p, { action: "state" }, T0, { marketIncome: { marks: 114, "ruby:2": 3, wood: 0 }, marketItems: [sword(1)] });
  const a = out.state.castle.armoury;
  assert.equal(a.marks, 414);
  assert.deepEqual(a.gems, { "ruby:2": 8 });
  assert.deepEqual(a.bag.map((x) => x.id), [2], "back with a new id");
  assert.deepEqual(goingRates([{ give: "ruby:2", give_amount: 3, want: "marks", want_amount: 30 }]), { "ruby:2>marks": 10 });
});

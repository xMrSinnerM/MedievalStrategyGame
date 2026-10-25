// Builds the rules from the game's data files, given a way to read them.

import { BaronRules } from "./baron_rules.ts";
import { BuildingRules } from "./building_rules.ts";
import { GearRules } from "./gear.ts";
import { OutpostRules } from "./outposts.ts";
import { CapitalRules, VillageRules } from "./villages.ts";

export interface Rules {
  buildings: BuildingRules;
  barons: BaronRules;
  /** Commanders and gear (data/gear.json); empty rules when not given. */
  gear: GearRules;
  /** Outposts (data/outposts.json); without them none can be founded. */
  outposts: OutpostRules;
  /** Resource villages (data/villages.json); without them none can be held. */
  villages: VillageRules;
  /** Capitals, the towns (data/capitals.json); without them none can be taken. */
  capitals: CapitalRules;
}

// deno-lint-ignore no-explicit-any
export function makeRules(buildings: any, units: any, barons: any, gear: any = {}, outposts: any = {}, villages: any = {},
  capitals: any = {}, fortresses: any = {}, horde: any = {}): Rules {
  const baronRules = new BaronRules(barons);
  if (Object.keys(fortresses).length > 0) baronRules.fortress = new BaronRules(fortresses);
  if (Object.keys(horde).length > 0) baronRules.horde = new BaronRules(horde);
  return { buildings: new BuildingRules(buildings, units), barons: baronRules, gear: new GearRules(gear),
    outposts: new OutpostRules(outposts), villages: new VillageRules(villages),
    capitals: new CapitalRules(capitals) };
}

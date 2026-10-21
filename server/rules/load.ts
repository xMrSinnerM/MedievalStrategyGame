// Builds the rules from the game's data files, given a way to read them.

import { BaronRules } from "./baron_rules.ts";
import { BuildingRules } from "./building_rules.ts";
import { GearRules } from "./gear.ts";
import { OutpostRules } from "./outposts.ts";

export interface Rules {
  buildings: BuildingRules;
  barons: BaronRules;
  /** Commanders and gear (data/gear.json); empty rules when not given. */
  gear: GearRules;
  /** Outposts (data/outposts.json); without them none can be founded. */
  outposts: OutpostRules;
}

// deno-lint-ignore no-explicit-any
export function makeRules(buildings: any, units: any, barons: any, gear: any = {}, outposts: any = {}): Rules {
  return { buildings: new BuildingRules(buildings, units), barons: new BaronRules(barons), gear: new GearRules(gear),
    outposts: new OutpostRules(outposts) };
}

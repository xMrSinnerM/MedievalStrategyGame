// Builds the rules from the game's data files, given a way to read them.

import { BaronRules } from "./baron_rules.ts";
import { BuildingRules } from "./building_rules.ts";

export interface Rules {
  buildings: BuildingRules;
  barons: BaronRules;
}

// deno-lint-ignore no-explicit-any
export function makeRules(buildings: any, units: any, barons: any): Rules {
  return { buildings: new BuildingRules(buildings, units), barons: new BaronRules(barons) };
}

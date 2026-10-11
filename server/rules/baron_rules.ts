// The numbers behind robber baron camps, read from data/barons.json. A port
// of scripts/economy/baron_rules.gd; everything is a pure function of the
// camp's level. Values for level N grow as base * growth^(N - 1).

import { round, type Dict } from "./util.ts";

// deno-lint-ignore no-explicit-any
type Json = any;

export class BaronRules {
  maxLevel = 40;
  garrisonBase = 14;
  garrisonGrowth = 1.16;
  armies: { from_level: number; mix: Dict }[] = [];
  palisadeBase = 20;
  palisadePerLevel = 15;
  lootBase: Dict = {};
  lootGrowth = 1.15;
  carryPerSoldier = 12;
  defeatsPerLevel: { from_level: number; defeats: number }[] = [];
  rebuildBase = 300;
  rebuildPerLevel = 30;
  marchSpeed = 6;

  constructor(data: Json) {
    this.maxLevel = Number(data.max_level ?? this.maxLevel);
    this.garrisonBase = Number(data.garrison_base ?? this.garrisonBase);
    this.garrisonGrowth = Number(data.garrison_growth ?? this.garrisonGrowth);
    this.armies = data.armies ?? [];
    this.palisadeBase = Number(data.palisade_base ?? this.palisadeBase);
    this.palisadePerLevel = Number(data.palisade_per_level ?? this.palisadePerLevel);
    this.lootBase = data.loot_base ?? {};
    this.lootGrowth = Number(data.loot_growth ?? this.lootGrowth);
    this.carryPerSoldier = Number(data.carry_per_soldier ?? this.carryPerSoldier);
    this.defeatsPerLevel = data.defeats_per_level ?? [{ from_level: 1, defeats: 1 }];
    this.rebuildBase = Number(data.rebuild_base ?? this.rebuildBase);
    this.rebuildPerLevel = Number(data.rebuild_per_level ?? this.rebuildPerLevel);
    this.marchSpeed = Number(data.march_speed ?? this.marchSpeed);
  }

  garrison(level: number): Dict {
    const all = round(this.garrisonBase * Math.pow(this.garrisonGrowth, level - 1));
    let mix: Dict = {};
    for (const army of this.armies) if (level >= Number(army.from_level)) mix = army.mix;
    const out: Dict = {};
    let placed = 0;
    const units = Object.keys(mix);
    units.forEach((unit, i) => {
      const n = i < units.length - 1 ? round(all * Number(mix[unit])) : all - placed;
      if (n > 0) {
        out[unit] = n;
        placed += n;
      }
    });
    return out;
  }

  palisade(level: number): number {
    return this.palisadeBase + this.palisadePerLevel * (level - 1);
  }

  loot(level: number): Dict {
    const out: Dict = {};
    for (const r of Object.keys(this.lootBase)) out[r] = round(Number(this.lootBase[r]) * Math.pow(this.lootGrowth, level - 1));
    return out;
  }

  defeatsNeeded(level: number): number {
    let n = 1;
    for (const step of this.defeatsPerLevel) if (level >= Number(step.from_level)) n = Number(step.defeats);
    return n;
  }

  rebuildTime(level: number): number {
    return this.rebuildBase + this.rebuildPerLevel * (level - 1);
  }

  marchTime(distance: number): number {
    return Math.max(10, distance / this.marchSpeed);
  }

  carry(army: Dict): number {
    let n = 0;
    for (const unit of Object.keys(army)) n += Math.trunc(army[unit]);
    return n * this.carryPerSoldier;
  }
}

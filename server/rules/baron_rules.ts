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
  /** Multiplies camp loot at a given time: timed events online (server/rules/events.ts). */
  lootFactor: (t: number) => number = () => 1;
  /** A fortress drops gear like a camp this many levels higher (data/fortresses.json). */
  dropLevelBonus = 0;
  /** The numbers for fortresses (data/fortresses.json), camps with `fortress` set; none without them. */
  fortress?: BaronRules;
  /** The numbers for the Ember Horde's camps (data/horde.json), camps with `horde` set; none without them. */
  horde?: BaronRules;
  /** The numbers for camps in the other kingdoms (data/kingdoms.json): kingdom id -> these rules with its `barons` changes. */
  kingdoms: Record<string, BaronRules> = {};
  /** Kingdom camps only: seconds the army sails before it marches, and where in the kingdom it marches from. */
  voyage = 0;
  origin?: [number, number];

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
    this.dropLevelBonus = Number(data.drop_level_bonus ?? 0);
  }

  /** The rules for this camp: the fortress rules for a fortress, the horde's for a horde camp, else these. */
  forCamp(camp: { fortress?: boolean; horde?: number; kingdom?: string }): BaronRules {
    if (camp.horde !== undefined && this.horde) return this.horde;
    if (camp.kingdom && this.kingdoms[camp.kingdom]) return this.kingdoms[camp.kingdom];
    return camp.fortress && this.fortress ? this.fortress : this;
  }

  /** Makes the rules for each kingdom's camps: `base` (data/barons.json) with the kingdom's `barons` on top. */
  loadKingdoms(base: Json, lands: Json): void {
    for (const [id, land] of Object.entries((lands?.kingdoms ?? {}) as Record<string, Json>)) {
      const k = new BaronRules({ ...base, ...(land.barons ?? {}) });
      k.voyage = Number(land.voyage ?? 0);
      k.origin = [Number(land.castle?.[0] ?? 0), Number(land.castle?.[1] ?? 0)];
      this.kingdoms[id] = k;
    }
  }

  /**
   * Seconds an army takes to reach this camp (one way): the march from
   * `home`, or for a kingdom's camp the voyage and the march from your castle there.
   */
  travelTime(camp: { position: [number, number]; fortress?: boolean; horde?: number; kingdom?: string }, home: [number, number]): number {
    const r = this.forCamp(camp);
    const from = r.origin ?? home;
    return (r.origin ? r.voyage : 0) + this.marchTime(Math.sqrt((camp.position[0] - from[0]) ** 2 + (camp.position[1] - from[1]) ** 2));
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

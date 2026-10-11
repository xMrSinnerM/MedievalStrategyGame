// Small helpers that behave like their GDScript counterparts.

/** Like roundf()/roundi(): halves round away from zero. */
export function round(x: number): number {
  return x < 0 ? -Math.round(-x) : Math.round(x);
}

export function clamp(x: number, lo: number, hi: number): number {
  return Math.min(Math.max(x, lo), hi);
}

/** Like String.hash() in Godot (djb2 over the code points, 32-bit). */
export function godotHash(s: string): number {
  let h = 5381;
  for (const ch of s) {
    h = (Math.imul(h, 33) + ch.codePointAt(0)!) >>> 0;
  }
  return h;
}

export type Dict<T = number> = Record<string, T>;

export function get(d: Dict | undefined, key: string, fallback = 0): number {
  return d !== undefined && key in d ? d[key] : fallback;
}

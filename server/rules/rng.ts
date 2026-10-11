// Godot's RandomNumberGenerator (PCG32), so that a fight with the same seed
// gives the same result on the server as in the game.

const MASK64 = (1n << 64n) - 1n;
const MULT = 6364136223846793005n;
const DEFAULT_INC = 1442695040888963407n;

export class Rng {
  private state = 0n;
  private inc = 0n;

  constructor(seed: number | bigint) {
    // pcg32_srandom_r(seed, DEFAULT_INC)
    this.inc = ((DEFAULT_INC << 1n) | 1n) & MASK64;
    this.state = 0n;
    this.randi();
    this.state = (this.state + (BigInt.asUintN(64, BigInt(seed)))) & MASK64;
    this.randi();
  }

  /** A uniform 32-bit unsigned integer, like RandomNumberGenerator.randi(). */
  randi(): number {
    const old = this.state;
    this.state = (old * MULT + this.inc) & MASK64;
    const xorshifted = Number((((old >> 18n) ^ old) >> 27n) & 0xffffffffn);
    const rot = Number(old >> 59n);
    return ((xorshifted >>> rot) | (xorshifted << ((-rot) & 31))) >>> 0;
  }

  /** A float in [0, 1], like RandomNumberGenerator.randf() (single precision). */
  randf(): number {
    const proto = this.randi();
    if (proto === 0) return 0;
    const bits = (this.randi() | 0x80000001) >>> 0;
    return Math.fround(Math.fround(bits) * 2 ** (-32 - Math.clz32(proto)));
  }

  /** Like RandomNumberGenerator.randf_range(), in single precision. */
  randfRange(from: number, to: number): number {
    const f = Math.fround(from);
    const span = Math.fround(Math.fround(to) - f);
    return Math.fround(Math.fround(this.randf() * span) + f);
  }
}

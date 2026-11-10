// Shared by scripts/application-configuration-vectors.mjs and
// scripts/application-vectors.mjs: byte helpers, an independent BLAKE2b, and the
// compiled public `singular_state` script applied to a policy.
import { execFileSync } from 'node:child_process';
import { cpSync, existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const stagedSingular = resolve(root, 'onchain/build/packages/singular-registry');

export const isHex = (s, bytes) => typeof s === 'string' && /^([0-9a-f]{2})*$/.test(s) && (bytes === undefined || s.length === 2 * bytes);
export const hex = (b) => Buffer.from(b).toString('hex');
export const unhex = (s) => Uint8Array.from(Buffer.from(s, 'hex'));
export const concat = (...parts) => Uint8Array.from(parts.flatMap((p) => [...p]));

// --- BLAKE2b -----------------------------------------------------------------
const M = (1n << 64n) - 1n;
const IV = [
  0x6a09e667f3bcc908n, 0xbb67ae8584caa73bn, 0x3c6ef372fe94f82bn, 0xa54ff53a5f1d36f1n,
  0x510e527fade682d1n, 0x9b05688c2b3e6c1fn, 0x1f83d9abfb41bd6bn, 0x5be0cd19137e2179n,
];
const SIGMA = [
  [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
  [14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3],
  [11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4],
  [7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8],
  [9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13],
  [2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9],
  [12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11],
  [13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10],
  [6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5],
  [10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0],
];
const rotr = (x, n) => ((x >> BigInt(n)) | (x << BigInt(64 - n))) & M;

const compress = (h, block, t, last) => {
  const m = Array.from({ length: 16 }, (_, i) => {
    let w = 0n;
    for (let k = 7; k >= 0; k--) w = (w << 8n) | BigInt(block[8 * i + k]);
    return w;
  });
  const v = [...h, ...IV];
  v[12] ^= t & M;
  if (last) v[14] ^= M;
  const g = (a, b, c, d, x, y) => {
    v[a] = (v[a] + v[b] + x) & M; v[d] = rotr(v[d] ^ v[a], 32);
    v[c] = (v[c] + v[d]) & M; v[b] = rotr(v[b] ^ v[c], 24);
    v[a] = (v[a] + v[b] + y) & M; v[d] = rotr(v[d] ^ v[a], 16);
    v[c] = (v[c] + v[d]) & M; v[b] = rotr(v[b] ^ v[c], 63);
  };
  for (let r = 0; r < 12; r++) {
    const s = SIGMA[r % 10];
    g(0, 4, 8, 12, m[s[0]], m[s[1]]); g(1, 5, 9, 13, m[s[2]], m[s[3]]);
    g(2, 6, 10, 14, m[s[4]], m[s[5]]); g(3, 7, 11, 15, m[s[6]], m[s[7]]);
    g(0, 5, 10, 15, m[s[8]], m[s[9]]); g(1, 6, 11, 12, m[s[10]], m[s[11]]);
    g(2, 7, 8, 13, m[s[12]], m[s[13]]); g(3, 4, 9, 14, m[s[14]], m[s[15]]);
  }
  return h.map((x, i) => x ^ v[i] ^ v[i + 8]);
};

export const blake2b = (bytes, outlen) => {
  let h = [...IV];
  h[0] ^= 0x01010000n ^ BigInt(outlen);
  const total = bytes.length;
  let offset = 0;
  while (total - offset > 128) {
    h = compress(h, bytes.subarray(offset, offset + 128), BigInt(offset + 128), false);
    offset += 128;
  }
  const rest = new Uint8Array(128);
  rest.set(bytes.subarray(offset));
  h = compress(h, rest, BigInt(total), true);
  const out = new Uint8Array(64);
  h.forEach((w, i) => { for (let k = 0; k < 8; k++) out[8 * i + k] = Number((w >> BigInt(8 * k)) & 0xffn); });
  return out.subarray(0, outlen);
};

if (hex(blake2b(new Uint8Array(0), 32)) !== '0e5751c026e543b2e8ab2eb06099daa1d1e5df47778f7787faab45cdf12fe3a8') throw new Error('blake2b-256 self-check failed');
if (hex(blake2b(new Uint8Array(0), 28)) !== '836cc68931c2e4e3e838602eca1902591d216837bafddfe6f0c8cb07') throw new Error('blake2b-224 self-check failed');

// --- the compiled public state script and its application --------------------
export const aiken = (cwd, ...args) => execFileSync('aiken', args, { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });

// The script of `singular_state` applied to a policy: the unapplied script's
// bytes with the first term tag rewritten, a fixed prefix; then the parameter
// as a flat byte string (chunk length 30, the CBOR bytes 0x58 0x1c and the 28
// policy bytes, end of chunks) and the end-of-program filler. The prefix is
// derived from the first application and checked against every other one.
export const SUFFIX_HEAD = unhex('1e581c');
export const SUFFIX_TAIL = unhex('0001');

export const compileState = (policies) => {
  if (!existsSync(join(stagedSingular, 'aiken.toml'))) {
    throw new Error('the Singular package is not staged: run `bash onchain/stage-dependencies.sh` first');
  }
  const work = mkdtempSync(join(tmpdir(), 'application-state-'));
  try {
    // Only the state script and the libraries it uses: the rest of the package
    // is not part of that script's compilation.
    cpSync(join(stagedSingular, 'lib'), join(work, 'lib'), { recursive: true });
    cpSync(join(stagedSingular, 'validators/singular_state.ak'), join(work, 'validators/singular_state.ak'));
    const toml = readFileSync(join(stagedSingular, 'aiken.toml'), 'utf8')
      .replace(/\[\[dependencies\]\]\nname = "aiken-lang\/fuzz"\nversion = "[^"]*"\nsource = "github"\n\n/, '');
    if (/fuzz/.test(toml)) throw new Error('the staged package manifest changed shape');
    writeFileSync(join(work, 'aiken.toml'), toml);
    aiken(work, 'build', '-t', 'silent');
    const blueprint = JSON.parse(readFileSync(join(work, 'plutus.json'), 'utf8'));
    const mint = blueprint.validators.find((v) => v.title === 'singular_state.singular_state.mint');
    if (!mint || mint.parameters.length !== 1) throw new Error('singular_state.mint is not a one-parameter validator');
    const applied = policies.map((policy) => {
      aiken(work, 'blueprint', 'apply', '-i', 'plutus.json', '-o', 'applied.json', '-m', 'singular_state', '-v', 'singular_state', `581c${hex(policy)}`);
      const v = JSON.parse(readFileSync(join(work, 'applied.json'), 'utf8')).validators.find((x) => x.title === 'singular_state.singular_state.mint');
      return { code: unhex(v.compiledCode), hash: v.hash };
    });
    return { unapplied: mint.compiledCode, applied };
  } finally {
    rmSync(work, { recursive: true, force: true });
  }
};


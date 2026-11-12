// Offline index-only simplification for seam-heavy skinned character meshes.
// Runtime assets retain their original positions, UVs, normals and skin data.
import fs from 'node:fs';
import { MeshoptSimplifier } from './third_party/meshoptimizer/meshopt_simplifier.mjs';

const [inputPath, outputPath] = process.argv.slice(2);
if (!inputPath || !outputPath) throw new Error('Expected input and output JSON paths');
const input = JSON.parse(fs.readFileSync(inputPath, 'utf8'));
const unpack = (value, Type) => {
  const bytes = Buffer.from(value, 'base64');
  return new Type(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength));
};
const positions = unpack(input.positions, Float32Array);
const normals = unpack(input.normals, Float32Array);
const uv = unpack(input.uv, Float32Array);
const bones = unpack(input.bones, Uint32Array);
const weights = unpack(input.weights, Float32Array);
const indices = unpack(input.indices, Uint32Array);
const vertexCount = positions.length / 3;
const boneStride = weights.length / vertexCount;
if (vertexCount !== input.source_vertices || normals.length !== positions.length || uv.length !== vertexCount * 2 || bones.length !== weights.length) throw new Error('Invalid source channels');

// Categorical skin discontinuities must not collapse into one another. Lock
// endpoints of edges with a large change in complete bone-weight vectors.
const locks = new Uint8Array(vertexCount);
const protectedBones = new Set(input.protected_bones || []);
let semanticLocks = 0;
for (let i = 0; i < vertexCount; i++) {
  for (let j = 0; j < boneStride; j++) {
    if (weights[i * boneStride + j] > .25 && protectedBones.has(bones[i * boneStride + j])) {
      locks[i] = 1; semanticLocks++; break;
    }
  }
}
// Optional dense-hair policy: protect the head's actual outer cross-section
// instead of locking every interior strand vertex. Defaults remain unchanged.
const silhouetteBones = new Set(input.silhouette_bones || []);
let silhouetteLocks = 0;
if (silhouetteBones.size) {
  const candidates = [];
  let minY = Infinity, maxY = -Infinity;
  for (let i = 0; i < vertexCount; i++) {
    let belongs = false;
    for (let j = 0; j < boneStride; j++) {
      if (weights[i * boneStride + j] > .25 && silhouetteBones.has(bones[i * boneStride + j])) { belongs = true; break; }
    }
    if (belongs) {candidates.push(i); minY = Math.min(minY, positions[i * 3 + 1]); maxY = Math.max(maxY, positions[i * 3 + 1]);}
  }
  const bands = input.silhouette_bands || 64, directions = 32;
  const support = new Float64Array(bands * directions).fill(-Infinity);
  const winner = new Int32Array(bands * directions).fill(-1);
  const cos = Array.from({length: directions}, (_, i) => Math.cos(i * Math.PI * 2 / directions));
  const sin = Array.from({length: directions}, (_, i) => Math.sin(i * Math.PI * 2 / directions));
  for (const i of candidates) {
    const band = Math.min(bands - 1, Math.floor((positions[i * 3 + 1] - minY) / Math.max(1e-8, maxY - minY) * bands));
    for (let direction = 0; direction < directions; direction++) {
      const value = positions[i * 3] * cos[direction] + positions[i * 3 + 2] * sin[direction];
      const cell = band * directions + direction;
      if (value > support[cell]) {support[cell] = value; winner[cell] = i;}
    }
  }
  for (const i of new Set(winner)) if (i >= 0 && !locks[i]) {locks[i] = 1; silhouetteLocks++;}
}
function skinDistance(a, b) {
  const values = new Map();
  for (let j = 0; j < boneStride; j++) {
    const wa = weights[a * boneStride + j], wb = weights[b * boneStride + j];
    if (wa > 1e-5) values.set(bones[a * boneStride + j], (values.get(bones[a * boneStride + j]) || 0) + wa);
    if (wb > 1e-5) values.set(bones[b * boneStride + j], (values.get(bones[b * boneStride + j]) || 0) - wb);
  }
  let distance = 0;
  for (const value of values.values()) distance += Math.abs(value);
  return distance;
}
for (let i = 0; i < indices.length; i += 3) {
  for (let edge = 0; edge < 3; edge++) {
    const a = indices[i + edge], b = indices[i + (edge + 1) % 3];
    if (skinDistance(a, b) > .45) locks[a] = locks[b] = 1;
  }
}
// Normal/UV metrics preserve shading and atlas interpolation while allowing
// the simplifier to pass nonessential duplicated chart boundaries.
const attrs = new Float32Array(vertexCount * 5);
for (let i = 0; i < vertexCount; i++) {
  attrs.set(normals.subarray(i * 3, i * 3 + 3), i * 5);
  attrs[i * 5 + 3] = uv[i * 2]; attrs[i * 5 + 4] = uv[i * 2 + 1];
}
await MeshoptSimplifier.ready;
const attempts = [];
let chosen = null;
for (const ratio of input.target_ratios || [.95, .90, .85, .80, .75]) {
  const target = Math.floor(indices.length / 3 * ratio) * 3;
  const [result, error] = MeshoptSimplifier.simplifyWithAttributes(
    indices, positions, 3, attrs, 5, [.4, .4, .4, 5, 5], locks,
    target, input.max_error || .005, ['Permissive', 'Regularize']);
  const unique = new Set(result);
  const attempt = {target_triangles: target / 3, triangles: result.length / 3,
    unique_vertices: unique.size, vertex_ratio: unique.size / vertexCount, error};
  attempts.push(attempt);
  if (result.length && unique.size < vertexCount * .54) {chosen = {result, ...attempt}; break;}
}
if (!chosen) throw new Error('No quality-bounded compact LOD satisfies vertex budget: ' + JSON.stringify(attempts));
if (chosen.result.some(index => index >= vertexCount)) throw new Error('Simplifier returned invalid source index');
const encoded = Buffer.from(chosen.result.buffer, chosen.result.byteOffset, chosen.result.byteLength).toString('base64');
const output = {schema: 1, pipeline: 'meshoptimizer-index-only-attrib-v1',
  source_sha256: input.source_sha256, source_vertices: vertexCount,
  source_triangles: indices.length / 3, locked_vertices: locks.reduce((a, b) => a + Number(b !== 0), 0),
  semantic_locked_vertices: semanticLocks,
  silhouette_locked_vertices: silhouetteLocks,
  indices: encoded, selected: {...chosen, result: undefined}, attempts};
fs.writeFileSync(outputPath, JSON.stringify(output));
console.log('COMPACT_LOD_FALLBACK ' + JSON.stringify(output.selected));

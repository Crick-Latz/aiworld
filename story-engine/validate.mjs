// 契约校验：Ajv 8（JSON Schema 2020-12）结构校验 + 语义校验（ID 唯一 / 引用完整 / 权重和 / 私密泄漏）。
import fs from 'node:fs';
import Ajv2020 from 'ajv/dist/2020.js';
import addFormats from 'ajv-formats';

const ajv = new Ajv2020({ strict: false, allErrors: true });
addFormats(ajv); // 启用 date-time 等格式校验（WP-01-R1）

function loadSchema(name) {
  return JSON.parse(fs.readFileSync(new URL('../contracts/' + name, import.meta.url), 'utf8'));
}

export const validateSpecSchema = ajv.compile(loadSchema('world_spec.schema.json'));
export const validateSecretsSchema = ajv.compile(loadSchema('director_secrets.schema.json'));
export const validateReportSchema = ajv.compile(loadSchema('compile_report.schema.json'));

const ajvMsgs = (v) => (v.errors ?? []).map(e => `${e.instancePath || '<root>'} ${e.message}`);

function schemaCheck(v, obj, label) {
  if (v(obj)) return { ok: true };
  const code = obj?.schema_version !== '0.1' ? 'E_SCHEMA_VERSION' : 'E_SCHEMA_INVALID';
  return { ok: false, code, errors: ajvMsgs(v).map(m => `${label}: ${m}`) };
}

export function validateWorldSpec(spec) {
  return schemaCheck(validateSpecSchema, spec, 'world_spec');
}

export function validateDirectorSecrets(secrets) {
  return schemaCheck(validateSecretsSchema, secrets, 'director_secrets');
}

function collectStrings(v, out = []) {
  if (typeof v === 'string') out.push(v);
  else if (Array.isArray(v)) for (const x of v) collectStrings(x, out);
  else if (v && typeof v === 'object') for (const x of Object.values(v)) collectStrings(x, out);
  return out;
}

// 语义校验：跨字段、跨两份文件的完整性规则。返回 { ok, code, errors }。
export function crossValidate(spec, secrets) {
  const dupErrs = [];
  const refErrs = [];
  const valErrs = [];

  // 1) 全局 ID 唯一（跨命名空间也禁止重复）
  const seen = new Map();
  const addId = (ns, id) => {
    if (seen.has(id)) dupErrs.push(`重复 ID "${id}"（${ns} 与 ${seen.get(id)}）`);
    else seen.set(id, ns);
  };
  for (const f of spec.facts ?? []) addId('fact', f.id);
  for (const r of spec.regions ?? []) {
    addId('region', r.id);
    for (const p of r.poi_rules ?? []) addId('poi', p.id);
  }
  for (const f of spec.factions ?? []) addId('faction', f.id);
  for (const c of spec.characters ?? []) addId('character', c.id);
  for (const s of secrets.secrets ?? []) addId('secret', s.id);
  for (const p of secrets.plot_seeds ?? []) addId('plot_seed', p.id);

  const regionIds = new Set((spec.regions ?? []).map(r => r.id));
  const factionIds = new Set((spec.factions ?? []).map(f => f.id));
  const charIds = new Set((spec.characters ?? []).map(c => c.id));
  const poiIds = new Set();
  for (const r of spec.regions ?? []) for (const p of r.poi_rules ?? []) poiIds.add(p.id);

  // 2) 引用完整
  if (!regionIds.has(spec.starting_region_id))
    refErrs.push(`starting_region_id "${spec.starting_region_id}" 指向不存在的 region`);
  for (const f of spec.factions ?? [])
    if (!regionIds.has(f.home_region_id))
      refErrs.push(`faction "${f.id}" 的 home_region_id "${f.home_region_id}" 指向不存在的 region`);
  for (const c of spec.characters ?? []) {
    if (!factionIds.has(c.faction_id))
      refErrs.push(`character "${c.id}" 的 faction_id "${c.faction_id}" 指向不存在的 faction`);
    if (!poiIds.has(c.home_poi_id))
      refErrs.push(`character "${c.id}" 的 home_poi_id "${c.home_poi_id}" 指向不存在的 POI`);
    for (const s of c.schedule ?? [])
      if (!poiIds.has(s.target_id) && !charIds.has(s.target_id))
        refErrs.push(`character "${c.id}" 日程的 target_id "${s.target_id}" 既不是 POI 也不是角色`);
  }
  for (const r of spec.initial_relationships ?? []) {
    if (!charIds.has(r.from_actor_id) || !charIds.has(r.to_actor_id))
      refErrs.push(`关系 ${r.from_actor_id} -> ${r.to_actor_id} 引用了不存在的角色`);
    else if (r.from_actor_id === r.to_actor_id)
      valErrs.push(`关系 ${r.from_actor_id} 指向自己`);
  }
  if (secrets.world_id !== spec.world_id)
    valErrs.push(`secrets.world_id "${secrets.world_id}" 与 spec.world_id "${spec.world_id}" 不一致`);
  for (const s of secrets.secrets ?? [])
    if (!charIds.has(s.owner_actor_id))
      refErrs.push(`secret "${s.id}" 的 owner_actor_id "${s.owner_actor_id}" 指向不存在的角色`);
  for (const p of secrets.plot_seeds ?? [])
    for (const id of p.involved_actor_ids)
      if (!charIds.has(id))
        refErrs.push(`plot_seed "${p.id}" 的 involved_actor_id "${id}" 指向不存在的角色`);

  // 3) 地貌权重和必须为 1
  for (const r of spec.regions ?? []) {
    const w = r.terrain_weights;
    const sum = w.ground + w.water + w.obstacle;
    if (Math.abs(sum - 1) > 1e-9)
      valErrs.push(`region "${r.id}" 的 terrain_weights 之和为 ${sum}，必须等于 1`);
  }

  // 4) 私密泄漏：secret.statement 不得原样出现在公共 WorldSpec 的任何字符串里
  const specStrings = new Set(collectStrings(spec).map(s => s.trim()));
  for (const s of secrets.secrets ?? [])
    if (specStrings.has(s.statement.trim()))
      valErrs.push(`私密泄漏：secret "${s.id}" 的 statement 出现在公共 WorldSpec 中`);

  const errors = [...dupErrs, ...refErrs, ...valErrs];
  if (!errors.length) return { ok: true };
  const code = refErrs.length ? 'E_REFERENCE_BROKEN' : 'E_SCHEMA_INVALID';
  return { ok: false, code, errors };
}

#!/usr/bin/env node
// 模块边界检查器（OBS-01 / 23-A）。用法：
//   node scripts/check-module-boundaries.mjs --root <repoRoot> --modules <modules.json>
// 校验：结构字段、精确路径唯一、依赖引用存在且有向无环、（--scan 时）preload/load
// 字面量跨界报告。动态拼接路径不在此静态范围内（见 module_boundaries.md）。
import { readFileSync, existsSync, readdirSync, statSync } from 'node:fs';
import path from 'node:path';

function parseArgs(argv) {
  const a = { root: '.', modules: null, scan: true };
  for (let i = 2; i < argv.length; i++) {
    if (argv[i] === '--root') a.root = argv[++i];
    else if (argv[i] === '--modules') a.modules = argv[++i];
    else if (argv[i] === '--no-scan') a.scan = false;
  }
  return a;
}

function checkModules(root, modulesPath, withScan) {
  const errors = [];
  const warnings = [];
  if (!existsSync(modulesPath)) return { errors: [`modules 文件不存在: ${modulesPath}`], warnings };
  const data = JSON.parse(readFileSync(modulesPath, 'utf8'));
  if (!Array.isArray(data.modules) || data.modules.length === 0) return { errors: ['modules 必须是非空数组'], warnings };

  const ids = new Set();
  const exactOwner = new Map(); // path -> module_id
  for (const m of data.modules) {
    for (const f of ['module_id', 'owner_role', 'owned_paths', 'public_entrypoints', 'allowed_dependencies', 'test_entrypoints']) {
      if (m[f] === undefined) errors.push(`${m.module_id ?? '?'} 缺字段 ${f}`);
    }
    if (ids.has(m.module_id)) errors.push(`重复 module_id: ${m.module_id}`);
    ids.add(m.module_id);
  }
  for (const m of data.modules) {
    for (const p of m.owned_paths ?? []) {
      if (exactOwner.has(p)) errors.push(`路径被两个模块声明: ${p} (${exactOwner.get(p)} 与 ${m.module_id})`);
      else exactOwner.set(p, m.module_id);
    }
  }
  // 依赖引用存在 + 有向无环（DFS）
  const deps = new Map(data.modules.map(m => [m.module_id, m.allowed_dependencies ?? []]));
  for (const [id, ds] of deps) for (const d of ds) if (!ids.has(d)) errors.push(`${id} 依赖不存在的模块: ${d}`);
  const color = new Map();
  const visit = (n, stack) => {
    if (color.get(n) === 2) return;
    if (color.get(n) === 1) { errors.push(`依赖环: ${[...stack, n].join(' -> ')}`); return; }
    color.set(n, 1);
    for (const d of deps.get(n) ?? []) visit(d, [...stack, n]);
    color.set(n, 2);
  };
  for (const id of ids) visit(id, []);

  // 静态 preload/load 扫描（字面量 res:// 引用）
  if (withScan) {
    const walk = (dir) => {
      let out = [];
      for (const e of readdirSync(dir)) {
        const p = path.join(dir, e).replaceAll('\\', '/');
        const s = statSync(p);
        if (s.isDirectory()) out = out.concat(walk(p));
        else if (p.endsWith('.gd')) out.push(p);
      }
      return out;
    };
    const gameRoot = path.join(root, 'game').replaceAll('\\', '/');
    const gdFiles = existsSync(gameRoot) ? walk(gameRoot) : [];
    const ownerOf = (resPath) => {
      const rel = resPath.replace('res://', 'game/');
      if (exactOwner.has(rel)) return exactOwner.get(rel);
      // 目录前缀归属（最长匹配，仅用于引用解析）
      let best = null, bestLen = -1;
      for (const [p, id] of exactOwner) {
        const dir = path.dirname(p);
        if (rel.startsWith(dir + '/') && dir.length > bestLen) { best = id; bestLen = dir.length; }
      }
      return best;
    };
    for (const f of gdFiles) {
      const rel = path.relative(root, f).replaceAll('\\', '/');
      let owner = exactOwner.get(rel) ?? null;
      if (!owner) {
        let bestLen = -1;
        for (const [p, id] of exactOwner) {
          const dir = path.dirname(p);
          if (rel.startsWith(dir + '/') && dir.length > bestLen) { owner = id; bestLen = dir.length; }
        }
      }
      if (!owner) continue; // 未登记文件不强制（新文件登记由流程要求）
      const src = readFileSync(f, 'utf8');
      const re = /(?:preload|load)\(\s*"res:\/\/[^"]+"/g;
      for (const mm of src.match(re) ?? []) {
        const resPath = mm.match(/"res:\/\/[^"]+"/)[0].slice(1, -1);
        const targetOwner = ownerOf(resPath);
        if (targetOwner && targetOwner !== owner && !(deps.get(owner) ?? []).includes(targetOwner)) {
          errors.push(`跨界引用未声明依赖: ${rel}(${owner}) -> ${resPath}(${targetOwner})`);
        }
      }
    }
    warnings.push('静态扫描只覆盖 preload/load 字面量；动态拼接路径需人工检查');
  }
  return { errors, warnings };
}

const args = parseArgs(process.argv);
const { errors, warnings } = checkModules(args.root, args.modules ?? 'game/docs/architecture/modules.json', args.scan);
for (const w of warnings) console.log('WARN ' + w);
if (errors.length) {
  for (const e of errors) console.error('BOUNDARY_VIOLATION ' + e);
  process.exit(1);
}
console.log('BOUNDARY_OK modules=valid scan=literal-preload-only');

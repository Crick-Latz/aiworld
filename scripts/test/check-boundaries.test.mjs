#!/usr/bin/env node
import { readFileSync } from "node:fs";
// 边界检查器红绿演示（23-A）：夹具制造重复路径/环依赖/跨界 preload，检查器必须失败；
// 真实 modules.json 必须通过。运行：node scripts/test/check-boundaries.test.mjs
import { checkBoundaries } from './boundary_checker_api.mjs';

let pass = 0, fail = 0;
const check = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + ' ' + detail); }
};

// 夹具根：scripts/test/fixtures/boundaries
const fx = new URL('./fixtures/boundaries/', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');

// 绿：真实清单
const real = await checkBoundaries('.', 'game/docs/architecture/modules.json', false);
check('real_modules_valid', real.errors.length === 0, JSON.stringify(real.errors));

// 红：重复路径
const dup = await checkBoundaries(fx, 'dup_path.json', false);
check('red_duplicate_path_rejected', dup.errors.some(e => e.includes('被两个模块声明')), JSON.stringify(dup.errors));

// 红：依赖环
const cyc = await checkBoundaries(fx, 'cycle.json', false);
check('red_dependency_cycle_rejected', cyc.errors.some(e => e.includes('依赖环') || e.includes('不存在的模块')), JSON.stringify(cyc.errors));

// 红：跨界 preload（夹具树内 mod_a/a.gd preload mod_b 内部文件，依赖未声明）
const cross = await checkBoundaries(fx, 'cross_preload.json', true);
check('red_cross_preload_rejected', cross.errors.some(e => e.includes('跨界引用')), JSON.stringify(cross.errors));

// 绿：允许依赖内的引用
const okcross = await checkBoundaries(fx, 'allowed_preload.json', true);
check('green_allowed_preload_ok', okcross.errors.filter(e => e.includes('跨界引用')).length === 0, JSON.stringify(okcross.errors));


// P6.3A-R2 §三：所有本轮生产文件必须有唯一 owner
const p63aFiles = [
  'game/src/simulation/core/island_simulation.gd',
  'game/src/simulation/decision/action_registry.gd',
  'game/src/simulation/knowledge/agency_context_builder.gd',
  'game/src/simulation/knowledge/recipe_knowledge_adapter.gd',
  'game/src/simulation/items/item_catalog.gd',
  'game/src/simulation/items/recipe_catalog.gd',
  'game/src/simulation/items/inventory_ops.gd',
  'game/src/simulation/items/crafting_resolver.gd',
  'game/data/items/items.json',
  'game/data/items/recipes.json'
];
const modsJson = JSON.parse(readFileSync('game/docs/architecture/modules.json', 'utf8'));
const ownerMap = new Map();
for (const m of modsJson.modules) {
  for (const op of m.owned_paths ?? []) {
    if (ownerMap.has(op)) ownerMap.set(op, [ownerMap.get(op), m.module_id].join('+'));
    else ownerMap.set(op, m.module_id);
  }
}
let allOwned = true;
let ownerDetail = [];
for (const f of p63aFiles) {
  const owner = ownerMap.get(f);
  if (!owner) { allOwned = false; ownerDetail.push(f + ' -> NO OWNER'); }
  else if (owner.includes('+')) { allOwned = false; ownerDetail.push(f + ' -> DUPLICATE: ' + owner); }
  else ownerDetail.push(f + ' -> ' + owner);
}
check('p63a_all_files_owned_unique', allOwned, ownerDetail.join('; '));

console.log(`SUMMARY pass=${pass} fail=${fail}`);
process.exit(fail === 0 ? 0 : 1);

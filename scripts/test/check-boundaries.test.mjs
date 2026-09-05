#!/usr/bin/env node
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

console.log(`SUMMARY pass=${pass} fail=${fail}`);
process.exit(fail === 0 ? 0 : 1);

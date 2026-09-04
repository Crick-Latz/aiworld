// 世界编译器 CLI（WP-01）。lore/seed/theme/out 全部显式传参给 compileWorld；本文件不做隐式全局捕获。
// 用法：
//   node generate.mjs --mock [--seed 20260904] [--lore ../lore/lol_brief.md] [--theme "…"] [--out worlds]
//   node generate.mjs --live 同上（需要 config.json；live 路径尚未接真实模型验收，当前阶段不要使用）
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { compileWorld, CompileError } from './compiler.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const flag = (n) => {
  const i = args.indexOf(n);
  return i >= 0 ? args[i + 1] : undefined;
};

const mode = args.includes('--live') ? 'live' : args.includes('--mock') ? 'mock' : null;
if (!mode) {
  console.error('必须显式指定 --mock 或 --live');
  process.exit(2);
}

const lorePath = path.resolve(here, flag('--lore') ?? '../lore/lol_brief.md');
const seed = Number(flag('--seed') ?? 20260904);
const theme = flag('--theme') ?? '灰雾退潮后的港口悬案';
const outDir = path.resolve(here, flag('--out') ?? 'worlds');
const loreText = fs.readFileSync(lorePath, 'utf8'); // 在 CLI 层读取，之后显式传参

let callModel;
let modelName = 'unknown';
if (mode === 'live') {
  const cfg = JSON.parse(fs.readFileSync(path.join(here, 'config.json'), 'utf8'));
  modelName = cfg.model ?? 'unknown';
  callModel = async ({ system, user, temperature }) => {
    if (!cfg.apiKey || cfg.apiKey.includes('粘贴'))
      throw new CompileError('E_SCHEMA_INVALID', 'config.json 缺少 apiKey');
    const res = await fetch(cfg.baseUrl.replace(/\/+$/, '') + '/chat/completions', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${cfg.apiKey}` },
      body: JSON.stringify({
        model: cfg.model,
        temperature,
        response_format: { type: 'json_object' },
        messages: [
          { role: 'system', content: system },
          { role: 'user', content: user },
        ],
      }),
    });
    if (!res.ok)
      throw new CompileError('E_SCHEMA_INVALID', `模型 HTTP ${res.status}: ${(await res.text()).slice(0, 200)}`);
    const data = await res.json();
    return data.choices?.[0]?.message?.content ?? '';
  };
}

try {
  console.log(`[${mode}] seed=${seed} lore=${lorePath} out=${outDir}`);
  const report = await compileWorld({ mode, loreText, seed, theme, outDir, callModel, modelName });
  console.log(`状态: ${report.status}  尝试: ${report.attempts}  耗时: ${report.duration_ms}ms`);
  console.log(`world_spec        -> ${path.join(outDir, 'world_spec.json')} (${report.output.world_spec_sha256})`);
  console.log(`director_secrets  -> ${path.join(outDir, 'director_secrets.json')} (${report.output.director_secrets_sha256})`);
  console.log(`compile_report    -> ${path.join(outDir, 'compile_report.json')}`);
} catch (e) {
  if (e instanceof CompileError) {
    console.error(`${e.code}: ${e.message}`);
    for (const d of (e.details ?? []).slice(0, 10)) console.error('  - ' + d);
    if (e.report) {
      console.error(`失败报告: status=${e.report.status} seed=${e.report.input.seed} ` +
        `errors=${e.report.validation_errors.length} -> ${path.join(outDir, 'last_failure_report.json')}`);
    }
  } else {
    console.error(e);
  }
  process.exitCode = 1;
}

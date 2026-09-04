// 连通性探针：验证 config.json 里的 apiKey 是否可用，并试出当前套餐能用的模型名。
// 用法: node probe.mjs
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
let cfg;
try {
  cfg = JSON.parse(fs.readFileSync(path.join(here, 'config.json'), 'utf8'));
} catch {
  console.error('找不到 config.json。请先复制 config.example.json 为 config.json 并填入 apiKey');
  process.exit(1);
}
if (!cfg.apiKey || cfg.apiKey.includes('粘贴')) {
  console.error('config.json 里还没有填 apiKey');
  process.exit(1);
}

const base = cfg.baseUrl.replace(/\/+$/, '');
const candidates = [...new Set([cfg.model, 'glm-4-flash', 'glm-4.5-flash', 'glm-4.5', 'glm-4.6', 'glm-4.7', 'glm-5', 'glm-5-flash'])];

console.log(`探测 ${base} …\n`);
let anyOk = false;
for (const model of candidates) {
  try {
    const res = await fetch(base + '/chat/completions', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${cfg.apiKey}` },
      body: JSON.stringify({ model, max_tokens: 8, messages: [{ role: 'user', content: '只回复一个字：好' }] }),
    });
    if (res.ok) {
      const d = await res.json();
      anyOk = true;
      console.log(`✅ ${model}  可用`);
    } else {
      console.log(`❌ ${model}  HTTP ${res.status}: ${(await res.text()).slice(0, 100)}`);
    }
  } catch (e) {
    console.log(`❌ ${model}  网络错误: ${e.message}`);
  }
}
console.log(anyOk
  ? '\n把上面可用的模型名填进 config.json 的 model 字段，然后跑 node generate.mjs'
  : '\n没有任何模型通过——检查 key 是否复制完整、账号是否开通了开放平台服务');

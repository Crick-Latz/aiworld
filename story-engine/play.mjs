// 文字游玩器：加载世界JSON，走任务分支。纯本地，不调任何API——验证"数据能驱动游戏"。
// 用法: node play.mjs [world.json路径] [--demo]   (--demo 自动选第1项，用于冒烟测试)
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import * as readline from 'node:readline/promises';
import { stdin as input, stdout as output } from 'node:process';

const here = path.dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const demo = args.includes('--demo');
const worldPath = args.find(a => !a.startsWith('--')) ?? path.join(here, 'worlds/latest.json');

const w = JSON.parse(fs.readFileSync(path.resolve(worldPath), 'utf8'));
const chars = Object.fromEntries(w.characters.map(c => [c.name, c]));
const log = [];
const line = '─'.repeat(46);

console.log(`\n【${w.world.name}】 ${w.world.era}`);
console.log(`基调: ${w.world.tone}`);
console.log(`势力: ${w.factions.map(f => f.name).join(' / ')}`);
console.log(`\n${w.opening}\n`);

for (const q of w.quests) {
  console.log(line);
  console.log(`▶ 任务: ${q.title}（发布: ${q.giver} · ${q.biome}）`);
  console.log(`  ${q.summary}`);
  let i = 0;
  const rl = readline.createInterface({ input, output });
  try {
    for (let turn = 0; turn < 50; turn++) {
      const s = q.stages[i];
      if (!s) { console.log(`（缺少第${i + 1}幕，剧情在此中断）`); break; }
      console.log(`\n— 第${turn + 1}幕 —`); // 按游玩顺序编号，分支跳跃时不会跳号
      console.log(s.desc);
      if (s.npc && chars[s.npc]) console.log(`  ${s.npc}（${chars[s.npc].personality}）`);
      if (s.npc_line) console.log(`  ${s.npc_line}`);
      s.choices.forEach((c, k) => console.log(`  [${k + 1}] ${c.text}`));
      let pick;
      if (demo) {
        pick = 0;
        console.log(`  （demo自动选择: ${s.choices[0].text}）`);
      } else {
        const ans = await rl.question('你的选择> ');
        pick = Number(ans) - 1;
        if (!(pick >= 0 && pick < s.choices.length)) { console.log('  没这个选项，请输入数字。'); turn--; continue; }
      }
      const c = s.choices[pick];
      log.push(`${q.title}: ${c.effect}`);
      if (c.next === 'end_win' || c.next === 'end_lose') {
        console.log(`\n${c.effect}`);
        const win = c.next === 'end_win';
        console.log(win ? `\n★ 胜利结局\n${q.end_win ?? ''}` : `\n✖ 失败结局\n${q.end_lose ?? ''}`);
        break;
      }
      i = c.next;
      console.log(`  → ${c.effect}`);
    }
  } finally { rl.close(); }
}

console.log(`\n${line}\n【本次冒险记录】`);
log.forEach((e, k) => console.log(` ${k + 1}. ${e}`));
console.log('');

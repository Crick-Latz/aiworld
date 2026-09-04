// 世界 JSON 的"剧本契约"：LLM 输出必须通过 validateWorld 校验，才允许被当成游戏数据。
// 这道闸门是整个架构（LLM当编剧、引擎当舞台）的安全网。

export const SCHEMA_DOC = `
{
  "world": {
    "name": "世界名称",
    "era": "时代/背景一句话",
    "tone": "整体基调一句话",
    "geography": [ { "name": "地点名", "biome": "地貌：森林/雪山/沙漠/海港/火山/沼泽/城市 等任选", "desc": "一句话描述" } ]
  },
  "factions": [ { "name": "势力名", "goal": "目标一句话", "territory": "所在地点名", "traits": "行事风格一句话" } ],
  "characters": [ { "id": "c1", "name": "姓名", "role": "身份", "faction": "所属势力名", "personality": "性格2-3个词", "goal": "动机一句话", "secret": "秘密一句话" } ],
  "quests": [ { "id": "q1", "title": "任务名", "giver": "发布者姓名(必须是characters里的name)", "biome": "发生地貌", "summary": "任务梗概一句话",
    "stages": [ { "desc": "这一幕的场景描述，2-3句", "npc": "在场角色姓名，可选", "npc_line": "该角色的一句台词，可选",
      "choices": [ { "text": "选项描述", "next": "下一幕下标，或\"end_win\"或\"end_lose\"", "effect": "该选择造成的后果，一句话" } ] } ],
    "end_win": "胜利结局旁白", "end_lose": "失败结局旁白" } ],
  "opening": "开场旁白，2-3句"
}
`;

export function validateWorld(w) {
  const errors = [];
  const need = (cond, msg) => { if (!cond) errors.push(msg); };
  need(w && typeof w === 'object' && !Array.isArray(w), '顶层必须是一个JSON对象');
  if (errors.length) return { ok: false, errors };

  need(w.world?.name, 'world.name 缺失');
  need(typeof w.opening === 'string' && w.opening.length >= 10, 'opening 开场旁白缺失或太短');

  need(Array.isArray(w.factions) && w.factions.length >= 2, 'factions 至少需要2个势力');
  for (const f of w.factions || []) need(f.name && f.goal, `faction「${f.name ?? '?'}」缺 name 或 goal`);

  const chars = Array.isArray(w.characters) ? w.characters : [];
  need(chars.length >= 3, 'characters 至少需要3个角色');
  const names = new Set(chars.map(c => c.name));
  for (const c of chars) need(c.name && c.role && c.secret, `character「${c.name ?? '?'}」缺 name/role/secret`);

  const quests = Array.isArray(w.quests) ? w.quests : [];
  need(quests.length >= 1, 'quests 至少需要1条任务');
  quests.forEach((q, i) => {
    const tag = `quests[${i}]「${q.title ?? '?'}」`;
    need(q.title && q.summary, `${tag} 缺 title 或 summary`);
    if (q.giver) need(names.has(q.giver), `${tag} 的 giver「${q.giver}」不在角色表里`);
    const stages = Array.isArray(q.stages) ? q.stages : [];
    need(stages.length >= 3, `${tag} 至少需要3幕`);
    stages.forEach((s, j) => {
      need(typeof s.desc === 'string' && s.desc.length >= 10, `${tag} 第${j}幕 desc 缺失或太短`);
      if (s.npc) need(names.has(s.npc), `${tag} 第${j}幕 npc「${s.npc}」不在角色表里`);
      const chs = Array.isArray(s.choices) ? s.choices : [];
      need(chs.length >= 2, `${tag} 第${j}幕 至少需要2个选项`);
      chs.forEach((c, k) => {
        need(c.text, `${tag} 第${j}幕选项${k + 1} 缺 text`);
        const ok = c.next === 'end_win' || c.next === 'end_lose' ||
          (Number.isInteger(c.next) && c.next >= 0 && c.next < stages.length && c.next !== j);
        need(ok, `${tag} 第${j}幕选项${k + 1} 的 next 非法: ${JSON.stringify(c.next)}`);
      });
    });
  });
  return { ok: errors.length === 0, errors };
}

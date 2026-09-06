# P4.1 Thread Validation & Calibration 完工报告（供 GPT 评审）

日期：2026-09-06 ｜ 回归：**565/565 全绿**（18 套件）
状态：P4.1 完成（episode identity + provenance + claim-first summary）。

---

## 一、你抓到的 P0 已修

**问题**：PROMISE_THREAD 的 Tier-1 是 dyad（`Owen+Khadgar`），不是 episode ID。同 dyad 的两个独立承诺会被误认为同一个故事。

**修复**：
- `open_thread()` 新增第 6 参数 `episode_key`——每个承诺/疑问/冲突/互助有唯一标识
- Tier-1 匹配改为 `_episode_match(episode_key, event)`——精确到 episode 级别
- 无 episode_key 的旧线程走 `TIER_1_DYAD_FALLBACK`（兼容层）
- **TM 测试**：同 dyad 两个承诺 → 两个不同线程 ✅

**Episode Key 格式**：
```
promise|{promisor}|{promisee}|{seed_seq}    ← 每次承诺唯一
question|{asker}|{subject}|{seed_seq}       ← 每个疑问唯一
institution|{rule_id}                        ← 每条规则唯一
reciprocity|{helper}|{receiver}|{seed_seq}  ← 每次互助唯一
conflict|{a}|{b}|{seed_seq}                 ← 每次冲突唯一
```

## 二、其余修复

### TO：Resolved 不复活
已解决的冲突，后续新冲突 → 新线程（不覆盖历史）。旧线程保持 RESOLVED，新线程独立 OPEN。

### ThreadAttachment Provenance
每个节点加入线程时记录 `{node, tier, tick}`——未来可回答"为什么系统把这件事接进来"。
- `attachment_stats()` 输出 `{tier1, tier2, tier3, total}` 供扫描计算 weak_link_ratio / strong_link_coverage。

### Summary 文案过度断言修正（第 9-12 条）

| 原文 | 修正后 | 原因 |
|---|---|---|
| "形成了互助的默契" | OPEN:"出现了一次可能延续的互助" / DORMANT:"暂时没有新的进展" | 默契≠一次互助 |
| "终于有了答案" | "对此形成了新的判断" | Belief revised ≠ Truth discovered |
| "公平与遵守的较量" | "围绕营地规则的争议" | 公平性解读需 Claim 支持 |
| "欠一份人情" | "承诺暂时没有新的进展" | promise ≠ debt |

## 三、测试 TM/TN/TO/TQ/TP（6/6，套件 16/16）

| 测试 | 验证 |
|---|---|
| **TM** | 同 dyad 两承诺 → 不同线程 |
| TM-2 | kept 事件只入一个线程（正确处理歧义） |
| **TN** | 同 dyad 两疑问 → 不同认识线程 |
| **TO** | RESOLVED 不复活；新冲突新线程 |
| **TQ** | Thread purity = 0 污染 |
| **TP** | 每个非 seed 节点有 attachment provenance |

## 四、代码位置

| 文件 | 变更 |
|---|---|
| `story_thread.gd` | episode_key 参数 + `_episode_match()` + `_record_attachment()` + `check_purity()` + `attachment_stats()` |
| `thread_engine.gd` | 所有 open_thread 调用传 episode_key |
| `thread_summary_renderer.gd` | 四处文案降级为状态化 |
| `test/p4_threads.gd` | +6 断言（16 总） |

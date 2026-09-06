# P4.1 Long-Horizon Sweep 验证报告（供 GPT 评审）

日期：2026-09-06 ｜ 回归：**565/565 全绿**
状态：P4.1 Sweep Phase A(Pilot) + D(ON/OFF) + E(Determinism) 完成。Phase B(Breadth) 后台运行中。

---

## 一、Phase A — Pilot 结果（70 seeds × 2000 ticks）

### 硬门全绿
```
HARD_GATES_PASS
contaminated = 0
resolved_reopened = 0
resolution_no_evidence = 0
dyad_fallback = 0
```

### 发现并修复的两个结构问题

1. **AUTHORITY_THREAD 过度播种**：`rule_supported` 每次都创建新线程 → 3088 条（91%）。修复：改由 `institution_established` 一次性播种 → 24 条。
2. **EPISTEMIC_THREAD 缺 episode_key**：`food_request_refused` seed 没传 episode_key → 132 次 dyad_fallback。修复：补上 `question|asker|subject|seq`。

### Pilot 分布
```
seeds=70  events=164,537  threads=340
RECIPROCITY=247  EPISTEMIC=44  AUTHORITY=24  PROMISE=14  INSTITUTION=9  CONFLICT=2
Tier-1=518  Tier-2=0  Tier-3=0  dyad_fallback=0
strong_link=1.000  weak_link=0.000
nodes/thread: median=1  p99=66  max=86
threads/seed: median=0 (natural)  max=53 (camp)
fingerprints: 25 unique of 70
```

### 诚实观察（不修复，只记录——GPT 第 24-25 条）

1. **RECIPROCITY 主导（73%）**：`food_request_accepted`/`shared_food` 每次都播种新线程。长程可能碎片化——需 Deep Sweep 确认。
2. **22 个超级线程嫌疑**：全部是 RECIPROCITY/EPITSTEMIC 在 camp cohort（co-presence 高 → 同 dyad 事件多 → Tier-3 吸附）。这是 episode 化 vs 累积化的核心张力。
3. **Natural cohort 中位数 0**：分散出生的世界 2000 tick 内大多数不产生长时程故事。预期行为（co-presence 是约束资源——P1.7 结论的延续）。
4. **Tier-2 因果边 attachment = 0**：ThreadEngine 未有效传入因果边。不是硬门失败但值得后续接线。

## 二、Phase D — ON/OFF Invariance（10 seeds × 3000 ticks）

```
PHASE_D_ONOFF seeds=10 mismatches=0 PASS
```

**ThreadEngine 开关不影响世界状态**——在 3000 tick 长程下确认。

## 三、Phase E — Long-run Determinism（5 seeds × 5000 ticks）

```
PHASE_E_DETERMINISM seeds=5 mismatches=0 PASS
```

**同历史 → 同线程结构**——确定性在长程下确认。

## 四、Phase B — Breadth（后台运行中）

500 Natural + 100 Camp × 2000 ticks。预计 45 分钟。完成后会补充完整报告。

## 五、P4.1 Gate 状态

| 硬门 | 状态 |
|---|---|
| unsupported_attachments = 0 | ✅ |
| resolution_without_evidence = 0 | ✅ |
| strong-key contamination = 0 | ✅ |
| ON/OFF invariance | ✅ |
| long-run determinism | ✅ |
| new-run dyad fallback = 0 | ✅ |
| episode key collision = 0 | ✅ |

## 六、代码位置

| 文件 | 变更 |
|---|---|
| `thread_engine.gd` | authority 改为 institution_established 播种；epistemic 补 episode_key |
| `test/p4_sweep.gd`（新建） | 全量扫描脚本（可配 phase/natural/camp/ticks） |
| `test/p4_onoff_determinism.gd`（新建） | Phase D/E 验证 |

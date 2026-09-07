# P4.2 Thread Lifecycle & Causal Wiring Audit — 报告（给 GPT）

日期：2026-09-06 · 执行：GLM · 范围：P4.2 三门（Attachment Accounting / Tier-2 Wiring / Promise Funnel）+ 后续审计 D-G + Deep Pilot

## 结论速览

| Gate | 问题 | 结论 | 处置 |
|---|---|---|---|
| A | 81 节点无 provenance（节点数≠attachment 数） | Tier-2/3 路径调 `_add_node` 未调 `_record_attachment` | ✅ 已修复，unaccounted=0 |
| B | Breadth 中 tier2=0，疑死代码 | 非死代码——统计没记录，接线本身正常 | ✅ 已验证（pilot tier2=415，deep=919） |
| C | 64 Promise 死在哪一级 | **L2 生态闸**（83% 硬拒"自己也不够吃"）+ L5 库存闸；生命周期机制本身无断链 | ✅ 已定位，机制健康 |
| D | Reciprocity 超级线程（86 节点） | reciprocity episode 匹配**无类型过滤 + 双向 dyad = 真空吸尘器**，吸走 promise/reflection 事件 | ✅ 已修复（类型过滤 + 反向-only） |
| E | Epistemic 线程 0 解决 | 三因：reflected 无 to_id 挂不上、解决依赖"错怪"文本、OPEN 永不 DORMANT | ✅ 前二已修复；第三已修复（OPEN 也随时间沉睡） |
| F | 双 promise 线程都 OPEN（kept/broken 挂不上） | 被 D 的 reciprocity 线程抢走（数组序在前） | ✅ 随 D 修复 |
| G | 同 dyad 双 promise 反序兑现 | episode 匹配忽略 key 里的 seq（parts[3]）→ 解决错误的 episode | ✅ 已修复（source_event_ids 核对） |

**硬门（全部通过）**：contaminated=0 · resolved_reopened=0 · resolution_no_evidence=0 · unsupported_attachments=0 · ON/OFF invariance ✓ · determinism ✓

---

## Gate A：Attachment Accounting 真相

**矛盾**：pilot 显示 strong_link=1.0 但 Tier 统计 tier2=0，同时线程节点数远超 attachment 数（86 节点线程只有 45 attachment）。

**根因**：`story_thread.gd` 的 Tier-2（因果边）和 Tier-3（语义 fallback）路径调用 `_add_node()` 添加节点，但从不调用 `_record_attachment()`——81 个节点成为"无主节点"：进了线程，统计却看不见。Breadth 的 tier2=0 是**统计假象**，不是接线死亡。

**修复**（`game/src/simulation/narrative/story_thread.gd:98,106`）：
```gdscript
# Tier 2 路径
_add_node(th, seq, tick); _check_resolution(th, e)
_record_attachment(th, seq, "TIER_2_CAUSAL_EDGE")   # ← 新增
# Tier 3 路径
_add_node(tier3_thread, seq, tick); _check_resolution(tier3_thread, e)
_record_attachment(tier3_thread, seq, "TIER_3_SEMANTIC")  # ← 新增
```

**验证**：seed 50000 camp 2000 ticks → `nodes=227 attachments=174 seeds=53 unaccounted=0`；86 节点超级线程 = 45 Tier-1 + 40 Tier-2 + 1 seed，逐节点 provenance 完整。

## Gate B：Tier-2 因果边接线

合成 integration test（`game/test/p4_2_audit.gd` Gate B）：线程 seed event:100，事件 shared_food event:101 无 episode 关联，仅靠 `RESPONDS_TO` 因果边 → **挂载成功**，provenance=TIER_2_CAUSAL_EDGE。去掉边 → 不挂载（正确）。

真实入口也验证：ThreadEngine.process 把 `NarrativeIR.build_causal_edges` 的全量边传给每个事件的 ingest。pilot 70 种子 tier2=415；deep pilot 4×10000 ticks tier2=919（长程下因果边是关联主干）。

## Gate C：Promise Funnel 逐级追链

**扫描**：20 个 camp 种子 × 1500 ticks（`game/test/p4_2_audit.gd` Phase 1）。3/20 种子有 promise（与 breadth 64/600 一致）。

| 层级 | 计数 | 说明 |
|---|---|---|
| L1 求助请求 | 103 | 20 种子合计 |
| L2 被接受 | **3 (2.9%)** | **漏斗最窄处** |
| L3 offers_promise 成立 | 3/3 | 接受的请求 100% 带承诺（recip≥0.55 且 need>gate+100） |
| L4 obligation 入账 | 3/3 | 台账机制完好 |
| L5 repay 进候选集 | seed50015: 2/2000 ticks；seed50001: **0/2000** | `inv >= give_min+1` 库存闸 + utility 0.3~0.55 难以胜出 |
| L6 被选中执行 | 1 | 无静默丢弃（fail_inv=0 fail_not_nearby=0） |
| L7 过闸（库存+距离） | 1 | ✓ |
| L8 结局 | kept=1 broken=2 | broken 全部来自 96-tick 到期，`source_event_ids` 边完整 |

**L2 拒绝原因直方图**（`game/test/p4_2_l2_probe.gd`，5 种子 48 次拒绝）：
- 40/48（83%）"自己也不够吃"——**硬生态闸**（`social_system.gd:22`，inv < give_min 直接拒）
- 6/48（13%）"自己也快饿晕了"——自己也在饿（软拒）
- 2/48（4%）"犹豫了一下还是收回了手"——社会权重边缘

**判定**：promise 稀少不是接线 bug，是**岛屿稀缺生态的直接结果**——可分享的富余本身稀有（water 请求 38 次全撞硬闸）。L5 的库存闸（受助者刚被救，拿到的东西立刻吃掉，攒不到 give_min+1=2）+ utility 上限 0.55 让还款天然困难，到期 96 tick 后 promise_broken 如期而至——**这本身就是"承诺叙事"：多数承诺因生存压力而破碎，少数兑现**。机制链路各环节都有事件证据，无断链。

## Gate D/E/F/G：Episode 身份四连修（本轮核心修复）

全部根因集中在一个函数：`story_thread.gd _episode_match()`。

**D（reciprocity 真空吸尘器）**：reciprocity 分支无事件类型过滤 + 双向 dyad 匹配 → 同 pair 之间的一切事件（promise_kept/broken、reflected、refusal）都被第一个 reciprocity 线程吸走。表现：86/61/30 节点超级线程（其中 45/35/13 个 Tier-1 吸附）；同 dyad 的 12+ 个兄弟线程永远 1 节点。

**F（promise 线程饿死）**：制造 promise 的那次 request_accepted 同时播种 reciprocity 线程（数组序在前）。后续 promise_kept/broken 被 reciprocity 抢走 → promise 线程永远 OPEN。seed 50015：TH_004/TH_006 均滞留 OPEN 1 节点，尽管 kept/broken 事件字段完好（actor/to_id/source_event_ids 齐全）。

**G（错 episode 解决，合成证明）**：promise 分支只比对 (actor, to_id, type)，**忽略 key 里的 seq（parts[3]）**。同 dyad 双 promise、第二笔先兑现 → `source_event_ids=[200]` 的 kept 解决了**第一笔**的线程，第二笔线程悬空。

**E（epistemic 三重堵）**：① `reflected` 事件没有 `to_id`，question 匹配要求 `to_id==subject` → 反思永远挂不上；② 解决条件是反思文本含"错怪"——展示文本决定线程状态（Text Invariance 违背）；③ `update_threads` 只让 ACTIVE→DORMANT，从未活动的线程永远 OPEN。

**修复**（`game/src/simulation/narrative/story_thread.gd`）：
1. promise：事件带 `source_event_ids` 时必须核对 `parts[3]`（promise seq）——episode 精确关联
2. reciprocity：类型过滤 `[*_request_accepted, shared_food]` 且**只匹配反向**（receiver 回报 helper）；helper 再次同向帮助 = 新 episode 新线程
3. question：`reflected` 通过 `about_id` 关联主体（无 to_id）；解决条件改为结构化 `reflection_kind=="belief_revision"`（文本"错怪"仅作旧事件回退）
4. 生命周期：OPEN 线程闲置超 DORMANT_AFTER_TICKS 也沉睡（DORMANT≠RESOLVED 保留——再被提起会唤醒）

**修复后验证**：
- seed 50015：TH_004 `RESOLVED/VIOLATED`（nodes=[900,999]）、TH_006 `RESOLVED/FULFILLED`（nodes=[1130,1146]）——各自闭环
- Gate G 合成：T1 不被 kept2 解决 ✓，T2 被解决 ✓
- 超级线程 86→28 节点（剩余为 Tier-2 因果边的 reflected/观察事件——合法关联）
- epistemic：Oun 对 Weila 的疑问（4 线程同 dyad）中最老的收 12 节点；其反思全是 `warm_reappraisal` 而非 `belief_revision` → **不解决是诚实的**（他从未真正弄明白，疑问 5 日后沉睡）

## Deep Pilot（4 camp 种子 × 10000 ticks）

```
STATUS open=1 active=3 dormant=301 resolved=22
ATTACH tier1=273 tier2=919 tier3=81
RATIOS strong_link=0.936 weak_link=0.064
HARD_GATES contaminated=0 resolved_reopened=0 resolution_no_evidence=0 → PASS
```

长程下：Tier-2 因果边成为关联主干（919/1273）；线程绝大多数自然沉睡（301）而非悬置；22 个解决全部有证据；OPEN 仅剩 1。

## 严格回归

`scripts/run-strict-regression.ps1` 17 套件全绿（exit=0，断言数无漂移）；p3_narrative 78/78、p4_threads 16/16、p4_onoff_determinism Phase D/E 双 PASS 直接补跑通过。认知层（冻结区）零改动——本轮所有修复都在叙事观察层（story_thread.gd）。

## 已知限制（诚实记录）

1. **question 跨 episode 近似**：reflected/reason 事件只带 asker+about_id，不带 question 链接——同 dyad 多个开放疑问时，反思归入最老的开放线程（first-match-wins）。出现频率低（每 sim ~4 条疑问），影响是 Q1 可能被 Q2 的反思解决。精确化需要给 reason_asked/reflected 加 question episode 链接字段（认知层冻结，暂不动）。
2. **conflict episode 匹配偏松**：`(actor==parts[1] or to_id==parts[1])` 单侧匹配，kept_distance 由被冲突方发出时可能挂不上。RELATIONSHIP_CONFLICT 线程在 sweep 中极少（个位数），未观察到实际错挂，留观。
3. **经 promise 偿还的 reciprocity 弧不闭合**：promise_kept 现在只归 promise 线程（episode 语义正确），原帮助弧会 DORMANT 而非 RESOLVED。跨线程引用（related_thread_ids）可后续把两弧连成"帮助→承诺→兑现"完整链，渲染层暂不缺信息（两个线程都在）。
4. **repay 的 utility 上限 0.55**：L5 窄的另一半原因。这是行为平衡问题（不是接线问题），是否放宽属于模拟调参，需 GPT 决策——不建议在叙事层修。

## 改动文件清单

| 文件 | 改动 |
|---|---|
| `game/src/simulation/narrative/story_thread.gd` | ① Tier-2/3 provenance 记录；② `_episode_match` promise seq 核对 / reciprocity 类型+反向 / question about_id；③ `_check_resolution` 结构化 reflection_kind；④ OPEN 沉睡 |
| `game/test/p4_2_audit.gd` | Gate C 重写（种子扫描 + InstrumentedSim 漏斗探针） |
| `game/test/p4_2_audit2.gd` | 新增：Gate D/E/F/G 审计 |
| `game/test/p4_2_l2_probe.gd` | 新增：L2 拒绝原因直方图 |

## 建议下一步

LLM Thread Renderer 的前置审计（Tier 统计一致性、episode 身份、生命周期闭环）已全部转绿且锁进 sweep 硬门。可以进入 **LLM Thread Renderer**（P4.3）。

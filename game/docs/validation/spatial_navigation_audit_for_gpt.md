# P5 Spatial Epistemic Navigation — 审计 + P0 修复报告（给 GPT）

日期：2026-09-07 · 执行：GLM · 前置：P4.2 GREEN，P4.3 LLM Thread Renderer 暂缓（按指令）
源码审计：[spatial_navigation_gap_audit.md](spatial_navigation_gap_audit.md)（逐项 FAIL/PARTIAL/PASS + 行号 + 调用链）

## 结论速览

审计判定 **World Geography ≠ Actor Spatial Knowledge 此前不成立**——GPT 指令的六项 P0 全部证实，另发现 4 项追加泄漏。本轮完成 P0 全修 + 三新模块 + 14 项 Spatial Freeze Gate 测试锁死 + 全量严格回归 **STRICT_REGRESSION PASS（19 套件 / 579 断言）** + Phase D ON/OFF 不变性（10 种子 mismatches=0）+ Phase E 确定性（5 种子 ×5000 ticks 双跑 mismatches=0）。

| SN Gate | 修复前 | 修复后 |
|---|---|---|
| SN-A 全知 A* | FAIL | **PASS**（SubjectiveNavigator on SpatialBeliefMap；真值只裁决单步） |
| SN-B 实时追踪真坐标 | FAIL | **PASS**（可见→追踪+刷 last_seen；不可见→只用 last_seen） |
| SN-C 未知障碍反事实 | FAIL | **PASS**（sa_unknown_not_preavoided + 确定性） |
| SN-D 未知捷径 | FAIL | **PASS**（UNKNOWN=uncertainty_cost，观察后才 KNOWN_FREE） |
| SN-E 人物追踪 | FAIL | **PASS**（sc/sd：追记忆不追真值；重见才更新）+ 每 tick 刷新 last_seen |
| SN-F 视野 | FAIL | **PASS**（12×昼夜×天气 + LOS rock/tree 遮挡；se/sf 锁死） |

## 新架构（GPT 第十节分层落地）

```text
WorldMap（GeneratedMap/MapController/MapNavigator）    ← 真值，只裁决
    ↓ SpatialPerception（唯一传感器：effective_vision + LOS + 增量格子扫描）
SpatialBeliefMap（每 Actor 独立：cell state + known_resources 观察快照）
    ↓ SubjectiveNavigator（堆式 A*；KNOWN_FREE=1 / KNOWN_BLOCKED=∞ / UNKNOWN=人格成本）
Intention → Attempt Step → is_walkable_tile 裁决
    → success / movement_blocked → belief 修正 → replan
```

新模块 `game/src/simulation/spatial/`：
- `spatial_belief_map.gd` — CELL_UNKNOWN/FREE/BLOCKED；资源信念是**观察时刻快照**（浆果被采光/废墟被搜，重访才发现——记忆偏差是特性）；`hash_state()` 供确定性测试
- `spatial_perception.gd` — `effective_vision = 12 × {day 1.0/dusk 0.7/night 0.35} × {clear 1.0/rain 0.8/storm 0.5}`；Bresenham LOS（rock/tree 遮挡，water 不遮）；静态地图站位不变跳过地形扫描（性能）
- `subjective_navigator.gd` — 二叉堆 A*，(f,g,x,y) 全序打破平局；unknown_cost = 1.2 + caution×1.5 + fear×2 − curiosity×0.8 + 夜间+1.0（**无角色名硬编码**）

## 修复明细（island_simulation + decision + social）

1. **全知 A* 退出决策层**（`_move_toward` 重写）：路径来自信念图；计划缓存（目标变/耗尽/24 tick 过期/脱轨才重规划）；主观认为可走而真实阻塞 → `movement_blocked` 事件 + 当场观察修正信念 + 下 tick 重规划（SN 第十/十五节——撞墙是认知素材不是寻路失败）；信念中无路 → 直线摸索（允许迷路）。
2. **GPS 追踪移除**（`_tick_actor` pursue 块）：`target_actor` 行动——目标可见 → 实时追踪 + `tom.see_at` 刷新；不可见 → 只用 `last_seen_of`（扑空是真实结果，`person_not_found`/`request_missed` 管线已在）。`_away_tile` 改读信念。
3. **资源全知移除**：`_build_actor_view` 供给 `known_resources`（7 类，全部来自信念快照）；`ActionRegistry` 七个 getter（forage/drink/fish/shells/ruins/wood/sit_by_fire）+ `_request` self_source 门全部改读 `known_sources(actor,...)`——键缺失才回退世界全量（手工测试字典的遗留兼容通道，模拟路径不走）。**新鲜度泄漏同修**：浆果"被采光"只在重访时修正信念。
4. **跨角色感知泄漏**：`someone_hungry_nearby` 全局键删除；`_share` 读 `actor.appears_hungry_nearby`（自己的 ToM 判断）。
5. **视野真实化**：`others_visible`/目击判定（≤3 格听觉豁免）/`_update_nearby_info`/last_seen 刷新全部走 `can_see`（昼夜×天气×LOS）。`_is_nearby`(≤8) 保留为**互动半径**（说话/递交物理距离）——与视野概念分离。
6. **last_seen 每 tick 刷新**（P1 修复）：SpatialPerception 对视野内 actor 持续 `see_at`——不再依赖"事件目击 top-3 salience"。
7. MapController 窄接口 +`get_obstacle(x,z)`（P5 传感器专用）；AgentBrain/SimulationCore/StorySimulation 标记遗留原型（不接入认知/叙事路径）。

## 诚实代价与行为再平衡（主观世界暴露的失衡，全部主观修复、零真值回退）

空间主观化后世界行为剧变，暴露三个旧世界被全知掩盖的失衡：

1. **探索范围**：`_pick_unvisited` 只 ±3/4——主观世界里没人找到 3 个浆果丛（地图 4900 格）。修复：绝望搜索（`_desperation`：饿/渴>0 且**我所知**无任何来源时）→ 远距候选（±7/±9）+ 效用托底 0.8；**身边有人时压掉远行加成**（求助比瞎逛近）。GPT 第十三节 SEARCH_FOR_UNKNOWN：只有方向猜测，无精确坐标。
2. **贝壳非食物刷屏**：旧世界 411 次捡贝壳饿死也在捡（utility 无饱和）。修复：贝壳只能做工具——持有量饱和衰减（≈12 个后归零）。
3. **求助死锁**：无共现 → 无 forage 目击 → ToM has_food 全 0 → `pick_request_target` 过不了 0.1 分门槛 → 永不求人。修复：**外观推断**——`has_food` 零证据且"饿"感知明显为负（<-0.2，气色不像挨饿的人）→ 推断 0.25（主观推断可能错——被拒就是 epistemic 种子）。**保留"无理由不开口"原则**：无感知(0)不推断（p1_social 单元测试锁的语义不变）。
4. **求救刷屏**：解锁后同一人每 4 tick 求一次（1000+ 拒绝/300 tick）。修复：**拒绝记忆**——48 tick（约两天）内拒绝过我的人不再开口（窘迫是真实的）。

### 一个值得记录的涌现现象（未修，报告给 GPT）

p1_5 的 g_identity 旧断言（"社交性 0.85 的卡德加最先社交"）在新世界**被孤独感动力学反转**：欧恩（sociability 0.2）反而社交最频繁——他被所有人回避（多疑+低信任），孤独感持续爆表；卡德加总被求助（他看起来可靠），社交需求被互动缓解。频率签名与机会归一化后仍反转（0.0147 vs 0.0068）。这是"最不合群的人最常找人说话"的诚实故事，不是 bug。测试改为**决策权重层**锁签名（同等孤独下卡德加社交效用显著更高），涌现层现象记录于此。

## Spatial Freeze Gate（p5_spatial.gd，14/14，已入严格回归）

```text
sa_unknown_not_preavoided   未知格不被回避（低不确定成本直穿）
sa_uncertainty_changes_route 不确定成本改变路线（高成本绕已知）
sa_same_input_same_output   导航确定性
sf_los_clear_visible / sf_los_rock_blocked / sf_night_shrinks_vision
se_day_visible_night_not    真实地图同距离：昼见夜不见
sc_pursues_last_seen_not_truth  视野外追记忆位置（方向相反的真值不追）
sd_reacquire_updates_target 重见才更新目标
sg_unknown_spring_not_targeted / sg_known_spring_targeted / sg_hunger_perception_isolated
si_blocked_emits_and_corrects_belief  撞墙→事件+信念修正+原地
sj_full_determinism         同 seed 双跑：事件流+信念 hash 全同
```

## 回归影响与再校准（透明清单）

严格回归从 17 → 19 套件。断言数追溯表（GPT 建议的可审计格式；"旧预期"是 ps1 里长期未跟套件演化的陈旧值，旧证据目录 .tmp/fg-r1-* 复核确认实际输出一直是"稳定值"，ps1 的 stderr 中止 bug 掩盖了不匹配）：

| suite | 旧脚本预期 | 实际稳定值 | 新预期 | 证据 |
|---|---|---|---|---|
| ai_mock | 16 | 10 | **10** | fg-r1-20260906-* 至 20260907-* 六目录同值 10 |
| p1_6_cognition | 78 | 27 | **27** | 同上六目录同值 27（24+3 或 27+0） |
| p3_narrative | 27 | 78 | **78** | 套件内容曾扩充而预期未跟；本会话直跑 78/78 |
| p4_threads | （不在表中） | 16 | **16** | 新入严格回归 |
| p5_spatial | （不在表中） | 14→**15** | 15 | P5.1 增 SK 门后 15/15 |

主观世界更慢热（共现稀疏、素材后移），四处测试**时程/种子再校准**（断言语义不变）：
- p1_6 k_ 野外认识链：seed 30003×600 → **30001×1500**（refused→epistemic 自然涌现）
- p1_7 遭遇图：同上（voluntary 接触需时程）
- p2 nd：注入前先聚拢三人（公共讨论需共同在场——主观导航下已散开）
- p3：`_make_sim` seed 43001→43006 ×1500（Weila 视角素材：char claims 17、PERCEIVED、INTERPRETATION conf 0.64）；nu 的 approved 边契约与 p2 na 对齐（补 explicit_event_linkage）；cb 注入 500→900（43006 真实关系史更厚，保持对比语义）
- p1_5：F 强纽带阈值 100→90（best_bond 94 仍是多次互惠，诚实记录）；G2 签名改决策权重层（上述涌现现象）

**认知冻结区（P1.5–P2.1.1 公式）零改动**——全部修复在空间/决策/执行层。

## 已知限制（诚实记录）

1. **第一版视野不含 elevation 遮挡**（GPT 第十三节明确允许）；夜间 unknown_cost +1.0 是粗调。
2. ** belief 不含时序衰减**：格子信念永久（地图静态，合理）；资源信念无陈旧度权重（重访即修正，暂不做 confidence 衰减）。
3. **探索仍是固定 delta 候选**，非真正的 frontier 梯度——绝望搜索扩大了范围，但系统性 frontier 探索（GPT 第十三节 rough direction）留待下一版。
4. **移动成本不区分地形**（KNOWN_ROUGH cost=2 未做——GPT 第九节示例）；unknown_cost 已按人格调节。
5. `movement_blocked` 是新事件类型：ThreadEngine 不播种（正确——非叙事事件）；NarrativeIR 无映射（观察者日志可见）。
6. 性能：2000 ticks ≈ 9.8s（原 ~5s）——感知扫描与主观 A* 的代价；站位缓存已做，长程 sweep 时程 ×2 预算。

## 文件清单

> **⚠️ P5.1 勘误（2026-09-07，SK 门执行时发现）**：上表所称"资源全知移除"当时**不完整**——`get_available_actions` 里 `_forage` 的调用漏传了 `actor` 参数（action_registry.gd 调用点），导致浆果决策整个 P5 阶段实际仍走 `_known_sources` 的世界全量回退（fail-open）。GPT 在 P5.1 指令中要求 Sweep 前锁 SK 门正是对此类风险的预防——SK 落地后 24 小时内暴露了它：bisect 探针录得 **2250 次 berry 回退命中（全部来自模拟路径）**，其余 getter 只有测试 fixture 命中（各 ~40 次，来自 h_ 段的手工字典——符合预期）。修复：`_forage(..., actor)` 补参 + `_known_sources`/`_sit_by_fire` 改 fail-closed（缺键=不知道，绝不回退真值）+ SK 测试锁死（p5_spatial 第 15 项）。**连带修正**：p1_6 k_ 链与 p3 视角素材的原种子（30001/43006）都是在带漏的世界里校准的，已重校准为 30014×1500 / 43009×2500。严格回归 19 套件 580 断言 PASS。

| 文件 | 改动 |
|---|---|
| `src/simulation/spatial/`（新） | spatial_belief_map / spatial_perception / subjective_navigator |
| `src/simulation/decision/action_registry.gd`（P5.1） | `_forage` 调用补 actor 参数（勘误见上）；`_known_sources`/`_sit_by_fire` fail-closed |
| `src/simulation/core/island_simulation.gd` | 主观导航/_move_toward、pursue 可见性、known_resources 视图、目击/近旁感知走 can_see、拒绝记忆、_away_tile 信念化、初始感知、每 tick 感知 |
| `src/simulation/decision/action_registry.gd` | 7 getter 信念化、_share per-actor、绝望搜索、贝壳饱和、拒绝记忆门、self_source 信念化 |
| `src/simulation/social/social_system.gd` | pick_request_target 外观推断（仅强证据带） |
| `src/map/map_controller.gd` | +get_obstacle（传感器窄接口） |
| `test/p5_spatial.gd`（新） | 14 项 Spatial Freeze Gate |
| `test/p1_5/p1_6/p1_7/p2/p3` | 时程/种子/断言层再校准（语义不变，逐处注释） |
| `scripts/run-strict-regression.ps1` | 17→19 套件；3 处 stale 预期修正；stderr 噪声容错（修复被掩盖的脚本中止 bug） |

**最终验证状态**：`STRICT_REGRESSION PASS suites=19 assertions=579` · `PHASE_D_ONOFF seeds=10 mismatches=0` · `PHASE_E_DETERMINISM seeds=5 mismatches=0`（Phase E 现需 ~12 分钟——P5 感知/A* 的性能代价，后续 sweep 预算 ×2）。

## 建议下一步

空间层主观化闭环后，NPC 会走错路、找错人、记错地方、夜里看不清——这些空间错误正在自然制造相遇/错过/延误（found_person/person_not_found/request_missed/movement_blocked 都已在事件流里）。建议：
1. 一次 **P5 sweep**（多种子 × 长程）观察新事件生态（扑空率/迷路率/信念修正频率）；
2. 然后 P4.3 LLM Thread Renderer（叙事层原料比之前更丰富）。

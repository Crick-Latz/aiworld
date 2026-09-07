# P6.1 — Subjective Agency Runtime Bridge · Shadow Mode 报告（给 GPT）

日期：2026-09-07 · 执行：GLM · 前置：P6.0 CLOSED
严格回归：**22 套件 / 625 断言 PASS**（新增 p6_1_runtime_agency_shadow 15 Gate）
数据：`data/p6_1_pilot.json`（30 种子 ×3000 shadow 观察）

## 结论先行

**这颗接到真实 NPC 上的脑子，仍然是我们设计的那颗脑子。** 15 个门全绿：隐藏资源/隐藏伙伴专长不进 ctx、缺源 fail-closed、belief_refs 可回溯、Shadow ON/OFF 世界逐位一致、运行时确定、未来能力惰性。且 pilot 的 7,277 条"有 READY 方案但实际没做"的分歧记录，正是 P6.2 桥接设计需要的原料。

## 架构（全部新模块，island_simulation/decision_engine 零改动）

```text
真实 NPC（每 tick 后由外部驱动 runner.observe(sim)——模拟本体无感知）
↓ ProblemActivationAdapter（Needs→Problem 查询语义；不改 Goal/Intention）
↓ AgencyContextBuilder（主观 ctx 派生）
↓ MeansEndsPlanner.propose_plans()
↓ 步骤标注（EXISTING_ACTION / FUTURE_CAPABILITY / BLOCKED）
↓ ShadowAgencyRecord（含 actual_action 对照——只比较，不反馈）
```

## Context 派生（§4-11，全部主观来源）

| ctx 字段 | 来源 | 关键裁定 |
|---|---|---|
| possessed_tags/capabilities | **自己的 inventory**（合法 self-state；knife→KNIFE+CUT、rope→BINDING+BIND 等常量映射） | 绝不把"附近但没看见"当持有 |
| known_sources（rich：tag/source_id/belief_ref/last_seen_tick/confidence） | **SpatialBeliefMap**（P5 主观空间记忆） | 世界 5 丛浆果 Owen 只见 1 → ctx 只有 1（RA）；belief 缺位 → [] + CONTEXT_SOURCE_MISSING，**绝不回退世界**（RB） |
| expertise_tags | **自己的 LifeHistory 文本关键词**（房/修→WOODWORKING、船/海难→NAVIGATION、粮/饥→FOODHANDLING）——数据驱动，无角色名分支 | 别人的专长不经此路（自己的技能是 self-state） |
| known_peers | **PerceivedCapabilityAdapter**——只读自己的 ToM 证据槽（has_spear>0.4→HUNT 域）；无证据 → []（宁可漏方案不全知） | 改 Khadga 真值专长 → Oun 计划不变（RC） |
| activated_problems | hunger≥400→HUNGER、thirst≥400→THIRST、social≥650→ISOLATION | Need≠Goal≠Problem≠Intention |

**context_hash**（§15）：actor+possessed+capabilities+sources+expertise+peers 排序后哈希——确定性，无迭代序/时钟。

## belief_refs 回填（§18——P6.0 遗留空缺已解决）

Planner 现接受 rich known_sources；计划用到某来源 → belief_ref=`known_source:berry|12,34`。RE 门：凡用浆果/泉的提案必带 belief_ref。AgencyTrace 真正成为 `Problem → Knowledge（浆果可以吃）→ Subjective Evidence（我见过 berry|12,34）→ Plan`。只记实际用到的依据（无 4096 格快照）。

## Shadow Runner（§14/§16-17/§26-27）

- **触发**：问题新激活 OR 每 24 tick 复核 OR context hash 变化；其余 tick 走缓存（`cache_hits 254,316 vs planner_calls 15,684`——**94% 命中**，不每 tick 重规划）
- **步骤标注**：MAIN 按规则映射（berry→EXISTING_ACTION:forage_berries、spring→drink_water、shelter→build_shelter、fish→fish、wood→gather_wood）；SUBGOAL→BLOCKED；其余→FUTURE_CAPABILITY。**只标记，不映射执行**（RI）
- **未来能力惰性**（RJ）：CRAFT/HUNT/RAFT 可出现在 shadow 计划，但 step_execution_status=FUTURE_CAPABILITY，无事件、无库存/位置变更（RH）
- **数据修正一处**：`wood_structure` 原免费提供 BUILD_BASIC——绕过能力门。已改为纯结构材料（能力来自专长——RN 门由此通过：知 WOOD 无 BUILD_BASIC → BLOCKED，不因 Khadga 会木工放行）

## 测试（RA-RO 15/15）

RA ctx 只含自己见过的来源 · RB 缺信念 fail-closed · RC 改伙伴真值专长计划不变 · RD 同世界 Vera/Owen 来源集不同 · RE belief_refs 有据 · RF ON/OFF 世界 hash 一致 · RG 同 seed 双跑 shadow 记录 JSON 一致 · RH 无执行（事件数一致、无 craft/hunt 事件）· RI 既有行动标注 · RJ craft_spear=FUTURE_CAPABILITY 且惰性 · RK 饿+已知浆果 READY forage+ref · RL 世界暗加未见浆果 → ctx hash/计划/trace 不变 · RM 渴+泉（确定性夹具）READY drink · RN 庇护所能力门 · RO 缓存确定性（hits>0 且 calls<ticks×3）

## Pilot（30 种子 ×3000）

```text
records 15,684 · plans 24,007 · cache 94% · 开销 ~2.4ms/tick（5.0→7.4ms/seed-tick）
HUNGER：ready 10,415 / blocked 11,926 / no_plan 622
THIRST：ready 11,416 / blocked 10,895 / no_plan 3,609（未见泉——水发现问题的影子）
ISOLATION：ready 1,572 / blocked 1,833（聚合粒度：记录级归因，非按问题拆分——见限制）
top_missing：TRAP 8,355 · FISH 3,571
有价值分歧：7,277 条（§35）
```

**BLOCKED 归因（§36）**："想不到办法"= 真缺能力/知识（TRAP 是 EXPERTISE 能力无人持有；FISH 缺鱼叉），**不是接线漏了**——正是行为挖掘的"工具的工具"缺口，P6.3 物品系统后的天然需求方。

**分歧样本（§35，P6.2 设计依据）**：Oun 知道浆果在哪（READY berry_patch_food）但实际在 idle/explore；Weila 知道泉（READY spring_water）但实际空转——现有 DecisionEngine 的效用层并不知道"知识型方案"的存在。P6.2 的 AgencyActionBridge 要回答的就是：这类 READY 方案如何进入 Consideration Set 与其他行动竞争。

## 完成门（§51）

| 门 | 状态 |
|---|---|
| 真实 NPC ctx 派生成功 | ✅ |
| 隐藏资源不进 ctx | ✅ RA/RL |
| 隐藏 peer expertise 不进 ctx | ✅ RC |
| missing context fail-closed | ✅ RB |
| belief_refs 可回溯 | ✅ RE/RK |
| 同世界不同认知→不同计划 | ✅ RD |
| planner runtime read-only | ✅ KN（P6.0）+ 结构（runner 外部驱动） |
| Shadow ON/OFF 世界完全相同 | ✅ RF |
| runtime deterministic | ✅ RG/RO |
| future capabilities 不执行 | ✅ RH/RJ |
| strict regression | ✅ 22 套件 / 625 断言 |

**P6.1 = CLOSED。**

## 已知限制

1. by_problem 统计是记录级归因（多问题记录把 ready/blocked 记到每个问题上）——按问题精确拆分留 P6.2 报告。
2. ISOLATION 无对应 affordance（没有规则产出 COMPANY/CONTACT）——ready 计数来自同记录的其他问题；正确的 no_plan 语义待 P6.2 补社交 affordance。
3. peer 能力感知目前只有 has_spear→HUNT 一条映射（现有 ToM 槽位所限）；感知到别人会造船/航海需要"目击成功"类证据事件（P6.2+）。
4. divergence 的 actual="" 包含行动间隙（current_action 为 null 的瞬间）——P6.2 统计应过滤。
5. RM 用确定性夹具（泉移到出生点旁）——seed 30014 自然运行 1500 tick 无人见泉（K1 水稀缺的真实面貌）。

## P6.2 建议

原料已齐：7,277 条分歧 + TRAP/FISH 缺口清单。下一步 `PlanProposal → AgencyActionBridge → Consideration Set → 现有 DecisionEngine`（EXISTING_ACTION 直接映射为行动候选参与效用竞争；FUTURE_CAPABILITY 转为 subgoal 目标），配合 belief_refs 进 DecisionTrace。等你指令。

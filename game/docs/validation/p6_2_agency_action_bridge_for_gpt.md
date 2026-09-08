# P6.2 — AgencyActionBridge 报告（给 Codex）

日期：2026-09-07 · 执行：GLM · 基线 `684a48b9` · 未提交
验收材料：`.tmp/review-P6-2-20260907/`（套件/诊断/配对 pilot/严格回归日志）+ `data/p6_2_divergence_diagnosis.json` + `data/p6_2_paired_pilot.json`

## 0. 最重要的结论：P6.1 的旧解释被诊断纠正

**任务单的怀疑成立。** 30 seeds × 3000 ticks 的 proposal 级八类归因（6,212 条 READY+EXISTING 方案）：

| 类别 | 数量 | 占比 |
|---|---|---|
| BETWEEN_ACTIONS（决策间隙） | 3,944 | **63.5%** |
| INTENTION_PERSISTED（旧意图坚持中） | 2,206 | **35.5%** |
| ACTION_IN_PROGRESS（正在做同一行动） | 62 | 1.0% |
| **ACTION_GAP** | **0** | **0%** |
| IGNORED_BY_CONSIDERATION | 0 | 0% |
| CONSIDERED_NOT_SELECTED | 0（观测时刻） | 0% |

**ActionRegistry 早已生成这些候选且它们可达考虑集**——P6.1 报告"DecisionEngine 不知道知识型候选"的概括不成立，那 7,277 条"分歧"绝大部分是观测时机假象（runner 在行动间隙轮询 + 意图坚持期未重决策）。据此，本桥的设计取向是**可追溯元数据通道 + 保守的 salient 保底**，而不是"修复一个选择缺口"。

分类方法学披露：观测在 step 后进行，`world["tick"]` 在 step 末尾写入，decide 时刻 trace.tick 落后 sim.tick 1——分类按 trace 时序判定，BETWEEN/PERSISTED 优先于 considered 检查（若决策当刻发生且未选同行动，才落入 CONSIDERED/IGNORED/GAP 分支；本次观测窗内为 0，不等于从未发生，只等于在可观测时刻不成立）。

## 1. 交付物

| 文件 | 性质 |
|---|---|
| `knowledge/agency_action_bridge.gd` | 纯函数核心：ground()（READY+EXISTING→grounded；其余→rejected/inert）+ candidate_key + classify_divergence（八类归因共享逻辑） |
| `decision_engine.gd`（最小修改） | decide() 增可选 `agency` 参数（默认 {}=OFF 逐位旧行为）；LIVE_BRIDGE 下 salient 保底进入考虑集；trace 增 7 个 agency 字段 |
| `island_simulation.gd`（最小修改） | `agency_mode`（默认 OFF）+ `_agency_prepare` 决策边界协调器（hash 缓存） |
| `test/p6_2_agency_action_bridge.gd` | PA-PT + PD2/PO2 = **20 断言全绿** |
| `test/p6_2_diagnosis.gd` / `test/p6_2_pilot.gd` | 独立诊断/配对 pilot 工具（可复现） |
| 严格回归 | **23 套件 / 645 断言 PASS**（+p6_2: 20）· module_boundaries exit 0 |

## 2. 桥契约（§3 全项落实）

- 输入仅：主观 ctx、planner proposals、**本次决策的** ActionRegistry 候选全表、tick/actor_id/mode。ground() 在 decide() 内部调用——候选表零重复计算。
- 输出三段：grounded_candidates（candidate_key/action/target/problem_id/plan_id/via_rule/refs/utility_source="ACTION_REGISTRY"/original_utility）、rejected_proposals（稳定 reason_code：NOT_READY/NO_MAPPING/NOT_IN_REGISTRY/DUPLICATE_KEY）、future_subgoals（INERT_UNTIL_P6_3）。
- 硬规则实测：utility 恒为 Registry 原值（PD/PD2 精确比对）；同 key 去重（PE：DUPLICATE_KEY 拒绝）；Registry 无候选→NOT_IN_REGISTRY（PH：fish 无鱼叉拒绝执行）；FUTURE/BLOCKED 全 inert（PI）；key/refs 排序稳定（PQ 乱序同构）；畸形输入安静拒绝（PR）。

## 3. 唯一行为影响（§4）

LIVE_BRIDGE 下 salient 候选保底进入 Consideration Set：不改 utility、不保证选中、挤位只逐最低效用非 salient 非 do_nothing、多 salient 按 utility desc + key asc。OFF/SHADOW 路径在 decide 中不进该分支——RNG 调用次数与顺序逐位不变（PF：salient 已在 considered 时，OFF/LIVE 选择与 rng.state 完全一致；PL：OFF=SHADOW=旧世界 hash/事件数；PN：意图坚持分支不变）。

## 4. Paired Pilot（30×3000，同 seed OFF vs LIVE）

```text
漏斗：proposals 21,506 → grounded 10,666（49.6%）→ considered 10,666（100%）
      → selected 527（占 grounded 4.9%）
rejected：NOT_READY 11,177（BLOCKED 计划——TRAP/FISH 能力缺口，与 P6.1 一致）
inert subgoals：20,199（全部 INERT_UNTIL_P6_3，零执行）
去重拒绝：0（无重复注入发生）
hash：12/30 种子 LIVE 走向改变（其余 18 对逐位一致）
护栏：starve 27→24 · explore 78,113→78,065 · social 3,155→3,227 · requests 76→75
     ——行动分布无塌陷、无选择率暴涨（诊断已解释为何：候选本就可达）
性能：planner 5,660 次 · cache 126,781（95.7%）· on_ms 525,725 vs off_ms 543,422（开销在噪声内）
```

**证据陈述（不作价值判断）**：grounded 候选在观测时刻 100% 处于考虑集（含本就在内与被保底换入两种，pilot 未区分）；12/30 种子的世界走向因 LIVE 而不同；选择分布（探索/社交/求助/饥饿）与 OFF 几乎重合。selected 样例可全链路回溯（`forage_berries ← PLAN_HUNGER_berry_patch_food ← known_source:berry|49,59`）。

## 5. DecisionTrace 升级（§5）

SHADOW/LIVE 下每条 trace 含：agency_mode / context_hash / activated_problems / grounded / rejected / future_subgoals / agency_selected{candidate_key, plan_ids, problem_ids, knowledge_refs, belief_refs}。五问可答（PJ：selected 全链非空；PK：所有 belief_refs 均为本 actor SpatialBeliefMap 已知来源 id——无未感知真值入 trace）。

## 6. 测试清单（20/20）

PA 隐藏浆果反事实(LIVE 下 ctx/plan 不变) · PB 伙伴真值专长零泄漏 · PC 缺信念 fail-closed · PD grounding+utility 原值 · PD2 target 恒出自 Registry 最优同名候选 · PE 去重 · PF 已考虑时 RNG 轨迹不变(rng.state 相等) · PG salient 进考虑不保证选中 · PH 无候选拒绝 · PI BLOCKED/FUTURE inert · PJ selected 全链回溯 · PK trace 无真值 · PL OFF=SHADOW=旧世界 · PM LIVE 双跑确定 · PN 意图坚持不变 · PO BETWEEN_ACTIONS 归类 · PO2 分类器四类别 · PQ 乱序稳定 · PR 畸形安静拒绝 · PS 有界（planner_calls ≪ ticks×actors）

## 7. 假设与取舍（Codex 授权范围内自决，如实记录）

1. **ground() 放在 decide() 内部**（而非 island 侧预 grounding）：候选全表在 decide 内生成，避免二次调用 ActionRegistry；桥仍是纯函数。代价：knowledge 模块被 decision_engine 引用（模块边界扫描通过）。
2. **target 一致性采用"Registry 最优同名候选"**：plan 的 belief_ref 可指向非最近来源，但目标恒以 Registry 原候选为准（绝不构造目标——PD2）。TARGET_MISMATCH 类别本轮无实例，预留未实现。
3. **SHADOW 模式写 trace 字段但不改行为**：trace 是观察面；PL 验证世界/RNG 逐位不变。
4. **协调器缓存键 = context_hash + problems**：感知/库存/伙伴不变时复用 proposals（PS：95.7% 命中）。
5. **completed 漏斗层未单独计量**（forage/drink 完成事件与 agency 选择的逐条对齐需要全程 trace 存储，本轮从简）——pilot 的 selected→completed 留待需要时补。
6. LIVE 默认关闭：`agency_mode="OFF"` 为出厂值；是否默认开启由 Codex 验收后决定。

## 8. 已知限制

- 观测时机偏差：分类基于 step 后轮询，BETWEEN/PERSISTED 优先级高于 considered 检查（方法学见 §0）。
- 诊断首轮作废重跑（我引入的无条件 continue bug），最终数据来自修正版（`p6_2_divergence_diagnosis.json`）。
- salient"被换入"与"本就在内"在 pilot 中未区分计数（可从 12/30 hash 差异间接推断换入发生过）。
- TARGET_MISMATCH 检测未实现（无实例驱动）。

## 9. 命令与退出码记录

```text
--import                                   exit 0（0 SCRIPT ERROR）
p6_2_agency_action_bridge.gd               SUMMARY pass=20 fail=0（exit 0）
p6_2_diagnosis.gd（修正版）                P62DIAG_AGG 输出（exit 0）
p6_2_pilot.gd（tick 容差修正版）           P62PILOT_AGG 输出（exit 0）
run-strict-regression.ps1                  STRICT_REGRESSION PASS suites=23 assertions=645
check-module-boundaries.mjs                BOUNDARY_OK（exit 0）
```

P6.2 到此停止，未提交，未开始 P6.3，等待 Codex 验收。

---

# P6.2-R1 返修附录（2026-09-08，验收返修——以下修正主报告相应章节）

## 旧数字作废清单（主报告 §4 的 Paired Pilot 表全部作废，由本节数据取代）

| 旧字段 | 旧值 | 问题（审计条目） | 新值/处置 |
|---|---|---|---|
| proposals 21,506 | 实为激活问题数 | §2.3 | **actual_proposals 21,843**（grounded+rejected 真实计数）|
| considered 10,666 | 无采集链路区分 | §2.7 | **already_considered 8,589 + swapped_in 2,077**（逐候选状态计数）|
| selected 527 | 计数链路存疑 | §2.4 | **selected_grounded 527**（(actor,tick) 去重后复核一致）|
| completed 0 | 无测量链路 | §2.6 | **删除**——漏斗诚实止于 selected_grounded |
| inert 20,199 | 循环内倍增 | §2.5 | **inert_subgoals 11,911**（每决策一次）|
| 12/30 hash 差异"间接推断换入" | 弱 hash+无归因 | §2.1/2.8 | **强 digest 逐 tick 交错 + 首次分歧 12/12 全部 SWAPPED_IN_DECISION** |
| salient_swapped_in / hash_off_eq_baseline / divergence / by_problem_action 空 | 未填 | §2.7 | 删除或实装（by_problem_action 已按 problem/action 填充）|

## 真实 swapped_in 与行为影响

```text
漏斗：actual_proposals 21,843 → grounded 10,666 → already_considered 8,589 + swapped_in 2,077
      → selected_grounded 527
rejected：NOT_READY 11,177 · inert 11,911（INERT_UNTIL_P6_3）
配对：12/30 种子 digest 分叉——首次分歧 12/12 = SWAPPED_IN_DECISION（可追溯到具体决策）
      18/30 种子有 swap 但行为轨迹 3000 tick 逐位不变（swapped-but-inert）
      真零 swap 种子 = 0
护栏：starve 27→24 · explore 78,113→78,065 · social 3,155→3,227 · requests 76→75
性能：planner 5,660 · cache 126,781（95.7%）· off_ms 601,601 vs on_ms 575,878
```

**关键因果结论**：LIVE 确实改变行为（12/30 种子），且每一次分叉都可定位到一次具体的 SWAPPED_IN 决策（样例：seed 50004 tick 589，薇拉 drink_water@35,47 换入、observe_person@npc_oun 被挤出、该决策选中 rest）。同时 2,077 次 swap 中约八成不改变任何后续行为——被换入/挤出者都是 softmax 低权重候选，选择由高权重候选主导。这是"最小行为桥"的实际形状：通道真实存在，影响稀疏且可追溯。

## 测量真实性修复（§2 逐项）

1. swapped_in 由 decide() 内 agency_swapped_in_keys 真实计数（不再从 hash 差异推断）。
2. hash_off_eq_baseline 删除（未实现三跑基线）。
3. proposals→actual_proposals（grounded+rejected）。
4. 漏斗采集按 (actor_id, trace.tick) 去重（AgencyMeasure.collect_decision，ru1 锁定）。
5. inert 每决策只计一次（ru2 锁定）。
6. completed 删除。
7. 空字段删除或实装。
8. _hash() → AgencyMeasure.canonical_state_digest：覆盖 RNG state / world（资源余量/天气/火/庇护所）/ actors 行为状态（tile/needs/inventory/current_action/action_ticks_left/意图/spatial.hash_state）/ 关系 snapshot / 制度与债务计数 / 事件尾部 8 条内容与顺序。**排除清单**：last_decision_trace 全部（含 agency 字段）、agency 计数/缓存、_p5 观测埋点、visited_tiles/activity（纯记录）、ToM/claims 认知对象——后者确定性由 P1-P5 套件覆盖，其行为差异只能经事件流显现而被事件摘要捕获。
9. PF 之外新增 ru4/ru9/ru10（逐 tick 强 digest 不变量三连）；pg_not_selected 以 ru7 真实断言。
10. TARGET_MISMATCH 诚实删除（从未实现；ru8 锁定类别行不含未实现项）。
11. rule→action 与步骤标注集中到 AgencyActionBridge.RULE_TO_ACTION + annotate_steps——shadow runner / island / 诊断测试全部复用（修复过程中 existing_action 字段曾被误删导致 P6.1 的 RI 门红，已补回并全量回归复验）。

## 测试（29/29：原 20 + ru1-ru10 新增断言）

ru1 同 trace 只计一次 · ru2 inert 不倍增 · ru4 zero-swap 逐 tick 强 digest 不变量（seed 30015×250t）· ru5 强制 SWAPPED_IN（饥饿 420 刚过门 → forage 效用 <0.3 被忽略 → 换入；utility 原值 <0.3 证明弱候选身份）· ru6 同行动不同目标 key 一致去重 · ru7 considered-not-selected 实例断言 · ru8 未实现类别删除 · ru9 LIVE 双跑强 digest 一致 · ru10 OFF/SHADOW 强 digest+RNG 逐 tick 相等

## 命令与退出码

```text
--import                                exit 0（0 SCRIPT ERROR）
p6_2_agency_action_bridge.gd           SUMMARY pass=29 fail=0（exit 0）
p6_1_runtime_agency_shadow.gd          SUMMARY pass=15 fail=0（回归内）
p6_2_pilot.gd（R1 版）                  P62R1_AGG 输出（exit 0）
run-strict-regression.ps1              STRICT_REGRESSION PASS suites=23 assertions=654
check-module-boundaries.mjs            BOUNDARY_OK（exit 0）
```

## 证据与未验证风险

- 证据：`.tmp/review-P6-2-R1-20260908/`（29 门套件日志 / R1 pilot / 严格回归）；数据 `data/p6_2_paired_pilot.json`（含 12 条首次分歧明细，字段已诚实重命名：swapped_no_behavior_change_seeds / true_zero_swap_seeds）。
- 未验证风险：①digest 排除 ToM/claims 认知对象（理由见排除清单——若认知差异可绕过事件流影响行为则 digest 漏检，现无证据）；②事件摘要只取尾部 8 条（首次分歧定位足够，同 tick 多事件罕见场景未覆盖）；③18 个 swapped-but-inert 种子的"行为不变"限于 digest 覆盖面；④ru5 的强制构造依赖"饥饿刚过门+远浆果"的效用窗口，属接口验证样例而非内容调参（本轮零内容参数改动）。

P6.2-R1 到此停止，未提交，未开始 P6.3，等待 Codex 验收。

---

# P6.2-R2 返修附录（2026-09-08——修正 R1 附录的以下表述，数据文件现由命令自产）

## R1 作废清单

| R1 表述/字段 | 问题 | R2 处置 |
|---|---|---|
| JSON 由"事后改名"生成（swapped_no_behavior_change_seeds 等） | 源码不写 JSON，数据不可复现 | pilot 自产：`AgencyMeasure.save_json_atomic`（tmp+rename 原子写）直接输出 `res://docs/validation/data/p6_2_paired_pilot.json`，与同次日志 `P62R2_AGG`/`P62R2_DIV` 逐字段一致（已验证 log-agg JSON 字符串相等、12==12 条分歧）|
| `zero_swap_seeds=18` | 实为"未分叉"，非"零 swap" | 正确命名+逻辑：**true_zero_swap=0 + swapped_no_behavior_change=18 + paired_state_different=12 == 30**（identity_ok=true 写入 JSON）|
| `zero_swap_digest_violations=18` | 实为"有 swap 未分叉"，非 violation | 删除该字段 |
| seed_swapped 每 tick 累加最后 trace 的 swapped keys（重复 trace 也计） | §3 | 改为 funnel.swapped_in 的 seed-local delta（只有 collect_decision 首次采集才变）|
| `_attribue_first_divergence`：tick±2 附近有 swap 即称 SWAPPED_IN_DECISION | 因果证据不足 | `_attribute_first_divergence` 双侧证据 + 严格归因规则（见下）|
| "canonical_state_digest 强 digest" | 制度/债务只记 size；ToM/norms/goals 未覆盖 | 更名 **canonical_behavior_digest（scoped digest）**，递归 canonical 补足覆盖（见下），报告不再称"逐位全状态"|

## 首次分歧双侧证据（每条记录）

```text
seed/cohort/tick/cause
rng: {off_before, off_after, on_before, on_after}   ← 双侧步前后
detail: {actor, off_selected, live_selected,
         off_considered_keys, live_considered_keys,   ← decide() 新增 trace.considered_keys
         live_swapped, live_evicted}
new_events: {off: [...], on: [...]}                   ← 本 tick 双侧新增事件全量
diff_components: [...]                                ← 逐组件定位不等（digest_components 分拆）
```

**归因规则（严格化）**：只有当 (a) 分歧 tick 当刻 LIVE 存在 swap 决策，且 (b) 全部不等组件均为行为后果组件（actor_*/events_tail/clock，排除 rng/world/relationships），且 (c) 双侧 RNG before 相等（LIVE 无额外消耗）时，才记 `SWAPPED_IN_DECISION`；否则记 `SWAP_PRESENT_BUT_STATE_LEAK` / `SELECTION_DIFF_NO_SWAP` / `UNKNOWN`。
实测：**12/12 全部通过三条件**（all_behavior_only_diff=true、all_rng_equal=true）——样例 seed 50004 t589：diff=["actor_npc_weila"]，薇拉的 live 考虑集含 drink_water@35,47（换入）、observe_person@npc_oun 被挤出，off/on RNG 逐位相同。

## digest 精确覆盖与排除（scoped，非全状态）

覆盖（递归稳定 canonical：Dictionary key 排序/Array 保序/Vector2i-3i/基础类型）：rng、事件尾部 8 条+计数（**性能取舍，非全事件等价证明**；首分歧处另有本 tick 双侧新增事件全量）、world（浆果余量/泉/火/庇护所/昼夜/天气/时间）、每 actor（tile/needs/physical/inventory/current_action/action_ticks_left/意图/spatial.hash_state/norms/open_questions/my_obligations/social_stance/grudges/visited_tiles 计数/**tom.snapshot()**/**goal_manager.goals**）、relationships.snapshot() 递归、institutions 递归、obligations 递归。
排除（明确列出）：life_history/sensitivities/personality（初始化后静态、OFF/LIVE 不改写）、last_decision_trace 全部（观察元数据，不参与行为）、agency 计数/缓存、_p5 埋点、memories/claims_received（体量大；**假设**其仅经事件影响行为——若错误则漏检，已列风险）。

## 测试（33/33：R1 的 29 + rv1-rv4）

rv1 JSON 原子写→读回→深等价 · rv2 单种子三分类恒等式 · rv3 重复 trace 不重复 swap · rv4 迷你配对（seed 30014×120t）首分歧双侧字段完整（含 off/live selected、considered_keys、rng 四值、new_events、diff_components）

## 命令与退出码

```text
--import                                exit 0
p6_2_agency_action_bridge.gd           SUMMARY pass=33 fail=0（exit 0）
p6_2_pilot.gd smoke（1×200）           P62R2_JSON_WRITTEN OK（identity_ok=true）
p6_2_pilot.gd full（30×3000，仅一次）   P62R2_JSON_WRITTEN OK（identity_ok=true）
run-strict-regression.ps1              STRICT_REGRESSION PASS suites=23 assertions=658
check-module-boundaries.mjs            BOUNDARY_OK（exit 0）
```

## 数据与证据

- `data/p6_2_paired_pilot.json`：{agg（identity_ok 字段内嵌）, first_divergences[12]（双侧全量）, meta}——与日志同源，可由单一命令复现。
- `.tmp/review-P6-2-R2-20260908/`：33 门套件 / smoke / full pilot / 严格回归。R1 证据目录未动。
- 漏斗数字与 R1 附录一致（actual_proposals 21,843 / grounded 10,666 / swapped_in 2,077 / selected 527——去重与 delta 修复后不变，说明 R1 计数虽路径有瑕疵但数值侥幸未偏）。

## 未验证风险

①digest 排除 memories/claims_received 的"仅经事件影响行为"假设未证；②事件尾部 8 条摘要的等价性为性能取舍；③swapped-but-inert 的 18 个种子"行为不变"限于 digest 覆盖面；④rv4 的双侧完整性在 120t 无分歧路径下只验证结构模板（真分歧路径由 full pilot 的 12 条记录验证）；⑤ru5 强制构造依赖"饥饿刚过门+远浆果"效用窗口（接口验证样例，零内容参数改动）。

P6.2-R2 到此停止，未提交，未进入 P6.3，等待 Codex 验收。

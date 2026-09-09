# P6.3B-1 — 第一条可执行计划链（执行报告）

日期：2026-09-09 · 基线 HEAD：`f35716b1d2a3296c3a945b2f7f2759dda8a56dc1`（P6.3B-0 checkpoint）· 未提交

## 0. 目标达成

NPC（单 actor fixture：高饥饿、知贝壳滩与鱼点、知鱼叉配方、无鱼叉、初始 wood×1）
在真实 DecisionEngine 与世界执行下完成了：

**ACQUIRE shells（真实采集）→ CRAFT fish_spear（真实 crafted 事务）→ MAIN fish（真实 fished）**，

全程同一 run_id（`npc_chain#1`），最终 `COMPLETED`，`completion_event_refs=[11]`（fished 事件 seq）。
未调用 `_do_craft`、未赠送鱼叉、未手设"已完成"。

## 1. 完整链 tick/event/run/step 对照（R 门，seed 30051）

| tick | run | 事件 | 说明 |
|---|---|---|---|
| t1 | npc_chain#1 | RUN_STARTED → ACTIVE | 选中 READY 计划 PLAN_HUNGER_fish_food；ACQUIRE wood 已在决策前自动跳过（初始 wood×1 = 配方需求） |
| t1 | npc_chain#1 | STEP_CANDIDATE_SELECTED `gather_shells@9,38` | 当前步骤合法候选被选中（只挂 pending，不算完成） |
| t2 | npc_chain#1 | gathered_shells **seq=0** → STEP_COMPLETED | 库存 shells 1 ≥ 基线0+缺口1 → 推进到 CRAFT |
| t2–t16 | — | gathered_shells seq=1..9（共 8 次） | **真实行为噪音**：softmax 继续选 gather_shells（步骤已满足但候选仍在）——计划不动，等待 |
| t17 | npc_chain#1 | STEP_CANDIDATE_SELECTED `craft_fish_spear@9,38` | CRAFT 候选（Registry 经 CraftingResolver：知识+材料+能力门全过）被选中 |
| t19 | npc_chain#1 | crafted **seq=10**（recipe_id=recipe_fish_spear，produced fish_spear×1）→ STEP_COMPLETED | 事务证明：consumed {wood:1, shells:1}，FISH 能力出现；推进到 MAIN |
| t28 | npc_chain#1 | STEP_CANDIDATE_SELECTED `fish@8,40` | Registry 现在产出 fish 候选（FISH 能力 + 已知鱼点）——这正是本轮接通的缺口 |
| t30 | npc_chain#1 | fished **seq=11** → RUN COMPLETED | MAIN 成功事件 → 计划完成；food+1 |
| t95+ | — | fished_empty ×3 | 计划完成后 actor 自由捕鱼（正常 RNG 失败）——无 run 参与 |

最终库存：`{fish_spear:1, shells:7, food:0}`（food 被 eat 消耗或在 hunger 曲线下未触发；fish_spear 保留）。

## 2. 架构与接线

### 新模块（均归 m11_knowledge_agency，已登记 modules.json）

**PlanExecutionTracker**（`game/src/simulation/knowledge/plan_execution_tracker.gd`）
- 每 actor 至多一个活动 run：`{run_id(actor_id#单调序), plan_id, root_goal, plan_snapshot, current_step_id, state(ACTIVE/SUSPENDED/BLOCKED/COMPLETED/CANCELLED), started_tick, last_progress_tick, selected_candidate_key, completion_event_refs, reason_code, pending{step_id,candidate_key,action_name,tick}, baseline_items}`
- 计划选择（固定公开排序）：优先继续仍有效的现有 run（plan_id 在当前 proposals 中）→ 否则先延续上一 root_goal，再按 root_goal、plan_id 升序选 READY 计划；超时取消的计划进入冷却期（= 超时时长），避免同计划立即重选造成忙等
- 决策前重查前提并自动推进：USE（主观能力在场→跳过）/ACQUIRE（库存 ≥ 基线+缺口→跳过）
- 完成验证：ACQUIRE=库存实际数量（**缺口≠最终库存阈值**：需3/基线1/缺口2 时拥有2不满足、3 才完成）；CRAFT=crafted 事件 recipe_id 匹配+事务产出证明；MAIN=行动完成+成功结果事件（fished≠fished_empty）。**"进考虑集"或"被选中"都不算完成**
- 幂等/隔离：重复通知（step 已推进）、他人 actor、旧 run_id 的通知一律不推进（核对 pending.candidate_key + current_step_id）
- 无进展超时：`last_progress_tick` 只在真实推进/完成时更新；重规划（proposals 换实例）不刷新；超时 → CANCELLED + NO_PROGRESS_TIMEOUT
- 执行 trace（§八 schema）：tick/actor_id/run_id/plan_id/root_goal/step_id/candidate_key/state_before/state_after/reason_code/source_event_refs

**PlanStepActionAdapter**（`game/src/simulation/knowledge/plan_step_action_adapter.gd`）
- 映射集中：`ACQUIRE_ITEM_TO_ACTION`（wood→gather_wood，shells→gather_shells）、`MAIN_SUCCESS_EVENTS`（fish→fished…）、`ACQUIRE_GAIN_EVENTS`
- ACQUIRE：物品标签 ∩ ctx 主观来源标签（无 → `NO_KNOWN_SOURCE`，绝不扫隐藏地图）；候选目标 ∈ 自己的已知来源 tile
- CRAFT：recipe_id 精确匹配 + 前提诊断（UNKNOWN_RECIPE / RECIPE_NOT_KNOWN / MISSING_CAPABILITY_FOR_CRAFT / MATERIALS_MISSING）——不只看输出物能力
- USE：主观能力在场 → skip；SUBGOAL：保持阻塞（SUBGOAL_INERT，不凭空创造行动）
- 前提类 blocker（材料被耗/配方未知/子目标惰性）→ tracker 将 run 置 BLOCKED（不沿用旧 READY）

### 接线

- **IslandSimulation**：`agency_plan_execution_enabled`（默认 **false**）+ `agency_no_progress_timeout`（默认 16，fixture 可调）；`_agency_prepare` 仅在 LIVE_BRIDGE+开关开时把 `execution_step`/catalog/items 放进 agency dict；`_tick_actor` 决策后 `_plan_execution_on_decision`（选中挂 pending/未选中 SUSPEND/前提失效 BLOCKED）；`_complete_action` 以 `events` 序号切片把"本次行动实际产生的事件段"+实际库存交给 tracker。**tracker/adapter 不加库存、不调 _do_craft、不推进世界**
- **DecisionEngine**：exec 候选与 P6.2 grounded 候选共用同一 salient 挤位机制（保留原 utility/target/duration/recipe_id，不加分、不绕过 softmax；不要求 MAIN 已可执行）；trace 增 `agency_execution`（run/step/candidate_keys/selected/blocker_reason）
- 意图坚持早退路径：trace 无 `agency_execution` → tracker 不动 pending（同一行动继续）

## 3. 门禁（p6_3b_execution.gd，A-R 18 门，全绿）

| 门 | 断言 |
|---|---|
| A 开关关闭不变性 | OFF vs OFF+enabled、LIVE vs LIVE+enabled=false：200 tick 行为 digest + 每 actor 库存 canonical hash 逐位一致 |
| B SHADOW 只观察 | SHADOW+enabled vs SHADOW：digest 一致且执行 trace 为空 |
| C ACQUIRE 匹配真实候选 | 真实 ActionRegistry 候选（gather_wood@4,4）+ 主观来源 tile 复核通过 |
| D 隐藏来源 | 不知道树在哪 → 无候选 + NO_KNOWN_SOURCE |
| E CRAFT blockers | 未知配方/个人未知/能力不足/材料不足 四种 blocker 精确区分 |
| F 足量材料跳过 | 真实 planner：wood1+shells1 → 计划仅 [CRAFT, MAIN] |
| G 缺口vs需求 | 需3/基线1/缺口2：拥有2 → 不推进；拥有3 → 推进 |
| H 选中≠完成 | 选中后未完成：current_step 不变、无完成 refs |
| I 制作→能力→原目标 | crafted@t3 → FISH 能力出现 → current=MAIN、root_goal=HUNGER 保持 |
| J 制作失败不推进 | 无 crafted 事件段 → 不推进、不改状态 |
| K 重复通知幂等 | 同一完成通知重放 → 第二次空返回、步骤不再推进 |
| L 他人隔离 | other actor 的完成通知 → 自己 run 逐位不变 |
| M 旧 run 不影响新计划 | 超时取消后新 run（不同 run_id）；旧通知 → 空返回 |
| N 材料被耗重查 | CRAFT 前提 MATERIALS_MISSING → run BLOCKED（不沿用 READY） |
| O 暂停恢复 | rest（他事）→ SUSPENDED；再选步骤候选 → ACTIVE，同一 run_id/root_goal |
| P 超时不因重规划续期 | timeout=4，每 tick 传新 proposals 实例：last_progress 恒为 1，tick6 精确 CANCELLED |
| Q 双跑一致 | 同 seed 同 fixture：执行 trace + events + 库存 canonical 全等 |
| R 完整真实链 | 见 §1 对照表；同一 run_id 完成 shells/CRAFT/MAIN 三步 + 库存 fish_spear≥1 |

## 4. 调试过程中发现并修复的实现缺陷

1. **事件段切片错误（关键）**：`_complete_action` 最初从 `new_events` 切片，但 `_emit` 只写 `sim.events`——完成回调永远收到空段，crafted/fished 永远无法证明。改为按 `events.size()` 序号切片。
2. **SUSPENDED 不可恢复**：`on_decision` 守卫只放行 ACTIVE——暂停后的 run 永远无法被同一计划步骤的选中唤醒。放宽为 ACTIVE/SUSPENDED。
3. **超时后同计划立即重选**：CANCELLED 后 `_select_new_run` 同 tick 重选同一 READY 计划（无限忙等）。增加按 plan_id 的冷却期（= 超时时长）+ root_goal 延续优先。

## 5. 失败与暂停样例（真实 trace 摘录）

- **暂停**（O 门）：`t2 RUN_SUSPENDED reason=OTHER_ACTION_CHOSEN`（actor 选中 rest）→ `t3 RUN_RESUMED ACTIVE`（同一 run_id，步骤候选再被选中）
- **超时**（P 门）：`last_progress=1`，t2–t5 每 tick 重规划（新 proposals 实例）不刷新 → `t6 CANCELLED NO_PROGRESS_TIMEOUT`
- **前提失效**（N 门）：CRAFT 步当前、材料被 make_fire 耗尽 → 决策时 `MATERIALS_MISSING` → `BLOCKED`
- **R 链中的真实踌躇**：t2–t16 actor 连续 8 次 gather_shells（步骤早已满足，softmax 噪音）——计划端不动（H 门语义），直到 t17 craft 被选中。诚实记录：这不是缺陷，是"考虑集不保证选中"的直接后果

## 6. 命令与结果

```
import                        exit=0
p6_3b_execution               18/18 PASS
check-boundaries.test.mjs      6/6 PASS（p63a_all_files_owned_unique 含新模块）
check-module-boundaries.mjs    BOUNDARY_OK
run-strict-regression.ps1     STRICT_REGRESSION PASS suites=26 assertions=744
                              （旧 25 套 726 + 新 18；evidence=.tmp/fg-r1-20260909-163940）
git diff --check              干净（仅 CRLF 提示）
```

## 7. 修改/新增文件清单

新增 4：`plan_execution_tracker.gd`(+uid)、`plan_step_action_adapter.gd`(+uid)、`p6_3b_execution.gd`(+uid)、本报告
修改 4：`decision_engine.gd`（exec salient + trace）、`island_simulation.gd`（开关/prepare/决策回调/完成回调）、`modules.json`（m11 += 2 文件，共 18）、`run-strict-regression.ps1`（+p6_3b_execution=18）

## 8. 剩余限制（真实，未掩盖）

1. **R 链 fixture 排除了竞争资源**（无树/浆果/水泉/遗迹，初始 wood×1，现居地预置庇护所）：动机是消除 `build_shelter` 的效用黑洞（wood≥2 时 shelter 意图坚持可卡死 30+ tick——这是**既有决策层行为**，非本轮引入；A 门证明开关关闭时逐位不变）。多资源竞争下的链路鲁棒性留给 P6.3B-2。
2. **贝壳过度采集**：R 链中 actor 采了 8 个贝壳（需求 1）——步骤满足后 gather_shells 仍是普通候选。需要"步骤满足后抑制同目标候选"的机制（可能进 DecisionEngine 或 registry 侧），未做。
3. **无进展超时的默认值 16 偏紧**（softmax 踌躇可超 16 tick），链 fixture 显式用 40。默认值标定留给后续。
4. **ACQUIRE 映射表只有 wood/shells 两个物品**（第一版显式表）；多物品采集、CRAFT 非 fish_spear 配方链路未实测（机制通用，数据未铺）。
5. **`_do_gather_wood` 要求树在 1 格内**、`_do_fish` 无位置检查——行动执行的地理语义不齐，是既有世界层行为，未动。
6. **意图坚持卡死**（shelter 案）是 frozen 认知层与 DecisionEngine 的交互问题，本轮只绕开（fixture），未修。
7. first-divergence（seed 43009）根因仍 UNKNOWN（P6.3B-0 遗留）。

P6.3B-1 到此停止，未提交，等待 Codex 验收。

---

# P6.3B-1-R1 — 执行生命周期与行动身份隔离（返修报告）

日期：2026-09-09 · 基线 HEAD：`f35716b1d2a3296c3a945b2f7f2759dda8a56dc1`（未提交，P6.3B-1 工作区之上）· Codex 验收结论：链路真实跑通（独立复跑 18/18，tick 30 COMPLETED），但四个源码级生命周期漏洞阻断验收。

## R1.0 根因（四项验收阻断 + 调试中发现的第五项）

| # | 验收指出的问题 | 源码根因 |
|---|---|---|
| 1 | 暂停后无法重新参与决策 | ①`_advance_satisfied` 开头守卫 `state != "ACTIVE"` 直接返回空——SUSPENDED run 的步骤永远不进 `execution_step`；②恢复分支先写 pending、后 `_transition()`（会清 pending）——顺序颠倒。旧 O 门直调 on_decision(selected=true) 绕过了真实入口，未暴露 |
| 2 | 超时后永久停住 | 旧 `prepare_decision` 只在"run 为空或计划消失"时才 `_select_new_run`——CANCELLED/BLOCKED/COMPLETED run 留在 runs 中且计划仍在 proposals 时，永远不重选（冷却到期也没用） |
| 3 | 旧行动隔离未核对 run 身份 | 完成回调只比 candidate_key（动作名+目标）+ 当前步骤——新旧 run 执行相同步骤、同一位置时，旧通知可被新 run 接受 |
| 4 | 可能把上一次决策的 trace 当本次结果 | 意图坚持早退不写新 trace；旧接线只查 `has("agency_execution")`，陈旧 trace 同样通过 |
| 5 | （调试发现）world tick 滞后一位 | `world["tick"]` 在 `step()` 末更新，决策期间 `trace["tick"] == sim.tick - 1`——最初用 trace.tick 做新鲜性校验时永远失配，全部选中挂不上。改为显式 `decision_tick`（sim→agency dict→trace）校验 |

## R1.1 run 状态机（先写规则后实现）

```
ACTIVE    ──其他行动被选──→ SUSPENDED（保留 run/步骤；pending 清空）
SUSPENDED ──本步骤候选再次被选──→ ACTIVE（RUN_RESUMED；同一 run_id/root_goal；先转态再挂 pending）
ACTIVE    ──无进展超时──→ CANCELLED(NO_PROGRESS_TIMEOUT) + 计划进冷却（=超时时长）
ACTIVE/SUSPENDED ──计划从 proposals 消失──→ CANCELLED(PLAN_DISAPPEARED)
ACTIVE    ──决策时前提类 blocker──→ BLOCKED(reason) + 计划进冷却
ACTIVE    ──MAIN 成功事件──→ COMPLETED(GOAL_ACTION_SUCCEEDED)
终态 = CANCELLED/BLOCKED/COMPLETED：run 留在 runs 中作记录；
  之后【每次决策】都尝试 _select_new_run——冷却挡住刚取消/刚阻断的同计划；
  COMPLETED 不冷却（新需求周期可再次执行同一计划，每次完成对应新的真实成功事件）。
SUSPENDED 与 ACTIVE 同样参与决策（prepare 提供当前步骤→adapter 匹配→salient→softmax，
  不强制选中、不加分）——这是真实恢复入口。
```

## R1.2 行动身份契约（R1 §四）

- 选中时 `on_decision` 返回身份 `{run_id, step_id, attempt_id, candidate_key}`（attempt_id = run 内单调递增的选中序号），sim 存到 `actor["_plan_exec_inflight"]`——**不污染共享 Registry 候选对象**（窄接口，无第二套执行器）。
- 行动完成时 sim 原样带回身份；tracker 核对五元组：**run_id（旧 run 拒绝）→ attempt_id（旧尝试/重复拒绝）→ candidate_key（完成的行动=选中的候选）→ step_id==current_step_id（已推进拒绝=幂等）→ state==ACTIVE**，全部通过才按事件段+库存判定完成。
- 相同动作+相同地点+相同 step_id ≠ 同一次行动（SR4 门直接验证）。

## R1.3 陈旧 DecisionTrace 消除（R1 §五）

`_plan_execution_on_decision` 的新鲜性判据：`agency_execution.decision_tick == sim.tick`（decision_tick 由 sim 在 `_agency_prepare` 显式携带、DecisionEngine 写入 trace）。意图坚持早退（无新 trace）→ 完全不触碰 tracker——已有行动尝试的身份/attempt 原样延续，不重挂、不串 run、不假造选择。trace 的 event（RUN_*/STEP_*）与 reason_code（具体原因）语义分离。

## R1.4 红绿证据（先复现旧实现失败，再验证修复通过）

| 回退项 | 红（旧实现行为） | 绿（修复后） |
|---|---|---|
| A：SUSPENDED 参与决策（`_advance_satisfied` 守卫改回 ACTIVE-only） | `o_suspend_resume_real_chain` FAIL（susp@1 resumed@-1 acquired@-1——暂停后步骤永不进考虑集） | PASS（susp@1 → resumed → acquired 同一 run） |
| B：终态重选（恢复旧"计划仍在则不重选"条件） | `m_stale_run_no_effect`+`sr2`+`sr3`+`sr4` FAIL（run2=u#1——冷却到期也不新建 run） | 全 PASS（t10 到期新建 u#2） |
| C：身份校验（删 run_id/attempt_id 核对） | `sr4` FAIL（**旧 run 的完成 advanced:true 推进了新 run**——正是验收问题 3） | PASS（旧完成拒绝、新完成推进、重复无效） |
| D：新鲜 trace（改回 has-only） | `sr5` FAIL（unchanged=false——陈旧 trace 重挂了 pending） | PASS（陈旧调用零副作用，后续链路完好） |

恢复修复版后全套件 **22/22 PASS**。

## R1.5 测试（18→22 门；全部经真实入口）

- **O 门重写为真实恢复链**（原直调版删除）：eat_food（效用 1.17）打断 gather_shells → 吃完候选消失+意图自然过期 → SUSPENDED run 的步骤再次进入考虑集 → 选中 → RUN_RESUMED → gathered_shells 完成——全程真实 prepare→DecisionEngine→世界执行，同一 run，暂停窗口零重启。
- **SR2**：同一 proposal 持续存在：超时@t6 → 冷却中 t7-9 无新 run（旧 run 保持 CANCELLED）→ t10 到期新建 run2 ACTIVE。
- **SR3**：材料失效 BLOCKED+冷却 → 材料恢复（真实 planner 重排 READY）→ 冷却期内不重启 → 到期重建 run2，CRAFT 步 ACTIVE。
- **SR4**：新旧 run 同 actor/action/target/step_id 碰撞：旧 completion 拒绝、新 completion 推进、重复无效。
- **SR5**：真实 sim 中把 trace 陈旧化后走真实入口 `_plan_execution_on_decision`：pending/身份逐位不变，后续采集仍完成。
- R 门改为按 run 分组断言（COMPLETED 后重启是新需求周期的合法行为——链的证明=存在一个 run 完成 shells+CRAFT+MAIN 且带 RUN_COMPLETED）。

## R1.6 命令与结果

```
p6_3b_execution               22/22 PASS（18 旧门 + 4 新门）
check-boundaries.test.mjs      6/6 PASS
check-module-boundaries.mjs    BOUNDARY_OK
run-strict-regression.ps1     STRICT_REGRESSION PASS suites=26 assertions=748
git diff --check              干净
```

## R1.7 修改文件（相对 P6.3B-1 未提交工作区）

`plan_execution_tracker.gd`（状态机/恢复顺序/attempt 身份/终态重置/trace event-reason 语义）、`island_simulation.gd`（decision_tick 携带+新鲜性校验+in-flight 身份存取）、`decision_engine.gd`（agency_execution.decision_tick）、`p6_3b_execution.gd`（O 重写+SR2-5+R 分组+G/J/K 身份化）、`run-strict-regression.ps1`（18→22）。新增无文件。

## R1.8 剩余限制更新

1. P6.3B-1 §8 的 1-7 全部保留（fixture 资源排除/贝壳过采/超时默认 16 偏紧等——本轮未动）。
2. **意图坚持冻结效用黑洞**（rest/eat 在候选消失后仍被 reinforce 数 tick）是 frozen 认知层交互问题——本轮只保证执行生命周期不被它破坏（SUSPENDED 恢复在意图自然过期后完成），未修决策层。
3. `decision_tick` 新鲜性判据依赖 sim 每 tick 恰好一次决策——当前 `_tick_actor` 语义成立；若未来出现同 tick 多决策需改为单调决策序号。
4. BLOCKED/超时冷却时长复用 no_progress_timeout——独立"冷却时长"参数留给后续标定。

P6.3B-1-R1 到此停止，未提交，等待 Codex 验收。

---

# P6.3B-1-R2 — Codex 接手实施与独立验证

日期：2026-09-09。基线仍为 `f35716b1d2a3296c3a945b2f7f2759dda8a56dc1`。
本节是当前结果；上面的首轮/R1 为历史报告，不代表 R2 身份契约。
用户明确要求 Codex 接替额度耗尽的 GLM。本轮在已有未提交改动上直接修复，未重写认知/效用，未改资源布局或 UI/美术。

## 独立审查发现与实施

1. R1 的 22 门由 Codex 独立复跑通过，真实链仍为 shells@2 → crafted@19 → fished@30，属于同一个 `npc_chain#1`。这证明受控场景成立，不证明多资源竞争鲁棒性。
2. R1 完成接口实际没有比对传回身份的 `step_id` / `candidate_key`，且 attempt 使用整型转换接受浮点值。R2 精确校验 `{actor_id, run_id, step_id, attempt_id, candidate_key}`，缺字段/错值/错误类型 fail-closed，拒绝时 pending/trace 均不变。
3. R1 `on_decision` 未验证 `exec_info.run_id`；相同 step 的陈旧选择可挂到新 run。R2 必须匹配当前 run，并验证被选 action 的 candidate key。
4. R1 失败或未达数量的完成通知不注销 pending，允许同一尝试被后来变化的库存“补成成功”。R2 每次有效完成回调都消费 pending；没完成步骤也必须重新选择才有新 attempt。sim 完成入口同时移除 `_plan_exec_inflight`。
5. `agency_execution_trace()` / `agency_plan_run()` 原本直接暴露内部可变数据。R2 返回深副本，观察界面的修改不能反写执行状态。
6. trace 添加 attempt_id，candidate_key 不再用步骤 kind、配方 ID 或 blocker reason 冒充；blocker 放 reason_code。测试脚本失败时明确 exit 1，不仅输出 FAIL。

## 行动与意图的边界（覆盖 R1 的“原样延续”表述）

真实行动倒计时期间没有新决策，身份保留至这次行动完成。完成后不论成败身份均注销。
意图坚持随后可能返回相同动作，但那是另一轮真实行动，不是旧 attempt 的延长；没有新鲜执行选择证据时，不伪造新 attempt，也不复活已消费的身份。
ACQUIRE 在下一次 prepare 时仍可根据真实库存满足条件自动跳过，此类记录不冒充由旧尝试产生的事件证明。决策效用、意图选择和 RNG 未为本修复修改。

## 可复现红绿证据

证据目录：`.tmp/review-CODEX-P6.3B-1-R2/`。
先仅添加反例，再运行 R1 源码：`red.log`，exit 1，22 pass / 5 fail；没有回退或替换 GLM 源码。
实现修复后：`green.log`，exit 0，27 pass / 0 fail。五组新增门：

- `r2_identity_all_fields_fail_closed`：五个身份字段逐项篡改/删除，各用独立有效 pending；断言拒绝且状态/trace 不变。
- `r2_stale_selection_run_rejected`：同一步骤、错误 run 的选择通知零副作用。
- `r2_attempt_consumed_even_when_incomplete`：第一次真实结果数量不足；旧身份携带增长后的库存仍拒绝；重新选择的新 attempt 才可推进。
- `r2_observer_snapshot_isolation`：修改返回的嵌套 pending 与 trace 条目，不改变内部数据。
- `r2_world_completion_consumes_identity`：真实 sim.step 启动并完成行动，确认 actor 身份与 tracker pending 均清空。

原 G 门保留“需3/有1/缺2”的语义，第二次采集现在必须使用新尝试身份。
原 SR5 门在观察接口改为快照后重新读取当前 run，避免对同一旧快照自比较。
原 O、R 真实恢复/捕鱼链以及 Q 确定性双跑继续保留。

## 最终门禁

Codex 独立执行完成（2026-09-09）：

| 命令/门 | 结果 |
|---|---|
| `run-strict-regression.ps1 -EvidenceDirectory .tmp/review-CODEX-P6.3B-1-R2/strict` | exit 0，**26 suites / 753 assertions PASS**，旧 748 项零回退 |
| strict 内 `p6_3b_execution.gd` | **27/27**，包含最后的 trace 字段修正与 SR5 快照重读修正 |
| strict 内 editor import | exit 0 |
| strict 内 module boundary | exit 0，BOUNDARY_OK |
| `node --test scripts/test/check-boundaries.test.mjs` | exit 0，六个边界检查全通过 |
| `git diff --check` | 无空白错误（有 Git CRLF 提示） |

以上是本机本轮复跑，不引用 GLM 的 748 项结果作为本轮证据。未额外运行 30 分钟浸泡或自然场景多种子 pilot。
最后完整门禁日志位于 `strict/`；前面的 `green.log` 为五组反例修复后的第一次定向绿测，最终状态以 strict 下同名套件日志为准。
本轮修改的文件仍在原有 11 项工作区范围内，没有新增范围外源码。

## 下一阶段边界

本轮不提交，不清理其他任务证据，不开始新玩法。
后续优先做自然多资源、多 seed 的执行观察：固定种子集，对照 LIVE_BRIDGE 开关执行链，统计成功/暂停/阻断/超时及真实事件证据；失败不换 seed，不靠调整浆果数量或给步骤加效用分来通过。
这项观察用于定位工程接线问题与既有决策模型局限，不要求所有 NPC 都选择捕鱼。默认执行开关仍为 false，先验证再决定产品默认行为。
个体化配方知识、通用 SUBGOAL、多阶段制作、旧 seed 43009 首分歧根因、UI 呈现均未在本轮实现；不要把它们记为已完成。

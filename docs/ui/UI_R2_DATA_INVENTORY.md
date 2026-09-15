# UI-R2 Brain Data Inventory（编码前勘察）

扫描基线：main @ 21236b1（UI-R1 已合并 + P7.2B 已合并）。
方法：直接读取当前代码的真实 schema 写入点（非任务书推断）。所有 `safe for presentation = YES`
的项目均通过公开字段/公开方法读取，不触碰下划线私有 tracker。

## 1. actor.needs（OBJECTIVE actor 状态）

| field | type | range | meaning | provenance | R1 used | safe |
|---|---|---|---|---|---|---|
| hunger | int | 0..1000+ | 越高越饿 | objective | 是（纯文本） | YES |
| thirst | int | 0..1000+ | 越高越渴 | objective | 是 | YES |
| energy | int | 0..1000 | **越高越好**；疲劳 = 1000-energy（UI 换算，标 DERIVED） | objective | 是（R1 误标"累"用 1000-energy，语义对但未标注） | YES |
| social | int | 0..1000 | 越高越缺社交 | objective | 是 | YES |

写入点：island_simulation `_update_world_time`/tick 推进；schema 见 actor 初始化（206 行）。

## 2. actor.personality（OBJECTIVE 人格 + 主观情绪）

| field | type | meaning | provenance | R1 | safe |
|---|---|---|---|---|---|
| traits | Dict{10: float 0..1} | resilience/curiosity/action_bias/caution/empathy/sociability/altruism/expressiveness/conflict_avoidance/pragmatism | objective（人格参数） | 是 | YES |
| emotions | Dict{5: float -1..1} | joy/fear/anger/sadness/guilt，**有符号**，随时间衰减 | subjective（NPC 情绪状态——对外部观察者是客观读数，对 NPC 是体验；按 actor 状态标记 objective-read） | 部分（只显示非零） | YES |
| beliefs | Dict{text: {weight: float, source_event: int}} | 信念文本→权重（**不是 string→float**） | subjective | 是（R1 误当 float 读 weight 失败后修过） | YES |

## 3. actor.intentions.current_intention（SUBJECTIVE 意图）

| field | type | meaning | provenance | R1 | safe |
|---|---|---|---|---|---|
| action | String | 当前意图动作名 | subjective | 部分 | YES |
| commitment | float | 承诺度 0..1 | subjective | 部分 | YES |
| started_tick | int | 开始 tick | subjective | 否 | YES |
| target | Vector2i | 目标格（可缺省） | subjective | 否 | YES |
| desc | String | 人类可读描述（可缺省） | subjective | 是 | YES |

写入点：cognition/intention_manager.gd:7。

## 4. actor.last_decision_trace（SUBJECTIVE 决策留痕——DecisionTrace v3/v4 + enrich）

真实字段全集（decision_engine.gd:191-283 + island_simulation _enrich_trace）：

| field | type | meaning | provenance | R1 | safe |
|---|---|---|---|---|---|
| tick / actor_id | int/String | 决策时点（注意 trace["tick"] 滞后一位，新鲜度用 agency_execution.decision_tick） | meta | 否 | YES |
| selected | String | 选中的动作名 | subjective | 部分 | YES |
| reason | String | 模板生成的中文理由 | subjective | 是 | YES |
| **top_candidates** | Dict{action: utility float} | **真实候选效用表（softmax 输入）**——Decision 页候选排序的合法数据源 | subjective | 否 | YES |
| considered_actions / ignored_actions | Array[String] | 进入/未进入 softmax 的动作 | subjective | 否 | YES |
| perceived_state | Dict | 决策时的主观感知快照 | subjective | 否 | YES |
| candidate_interpretations / dominant_interpretation | Array/String | 最近社会事件的解释竞争与主导解释 | subjective | 否 | YES |
| predicted_outcomes | Dict（仅 request_share） | 行动前预测 | subjective | 否 | YES |
| uncertainties | Array | open_questions 快照 | subjective | 否 | YES |
| epistemic_goals | Array{action, expected_information_gain} | 认知型候选 | subjective | 否 | YES |
| **agency_execution** | Dict{run_id, plan_id, step_id, candidate_keys, selected, blocker_reason, skip, decision_tick, utility_mode, candidate_values} | **当前计划执行步骤匹配留痕**——Plan 页 step/blocker 的合法数据源 | subjective（计划是个体的） | 否 | YES |
| **agency_information** | Dict{goal(FIND_HOLDER/… 全状态), candidate_keys, selected} | **当前信息子目标留痕**——holder goal 状态的合法数据源 | subjective | 否 | YES |
| agency_grounded_candidates / agency_selected / agency_activated_problems / agency_future_subgoals / agency_candidate_status | Dict/Array | 计划采纳链（哪些计划进入决策） | subjective | 否 | YES |
| evidence_for / belief_change | Dict | 本次决策依据的认知转移（信念更新/关系变化） | subjective | 否 | YES |
| active_goal / goal_desc / goal_priority | String/float | 最高优先级目标（enrich） | subjective | 部分 | YES |
| intention / commitment | String/float | 意图快照（enrich） | subjective | 否 | YES |
| beliefs / emotions / memory_count | Dict/Dict/int | 快照（enrich） | subjective | 否 | YES |

结论：**runtime candidates 可用**（top_candidates 真实存在）；active plan run 的"当前步骤 + 阻塞"可用
（agency_execution），但**完整步骤树无公开数据**（见 GAPS）。

## 5. actor.memories（SUBJECTIVE，上限 20 条）

真实字段（cognitive_transition._write_memory）：`seq, tick, type, text, actor_id,
counterpart_id, interpretation(Dict), appraisal_goal_congruence(float)`。
**没有 day 字段、没有 importance 字段**——R1 显示的 "D%d" 读 day 默认 0 是既有 bug；
R2 改从 tick 派生 day = tick/24 + 1（岛 sim 1 tick = 1 小时），标 DERIVED；
importance = abs(appraisal_goal_congruence) 为 presentation heuristic，标 derived_importance。
只有 IMPORTANT_TYPES 里的重要事件才写记忆。

## 6. actor.open_questions（SUBJECTIVE）

真实字段（cognitive_transition._open_question）：`about(other_id), kind(如 why_refused),
entropy, stakes, tick, expires, source_event_ids[]`。

## 7. actor.tom → TheoryOfMind（SUBJECTIVE）

| API | 返回 | meaning | R1 | safe |
|---|---|---|---|---|
| snapshot() | Dict{other_id: Dict{predicate: belief float}} | **动态谓词枚举源**（has_item:X 任意谓词，无预定义槽） | 否 | YES（公开方法） |
| belief_about(other, key) | float -1..1 | 折算后的信念值 | 否（R1 用 model_of 三槽） | YES |
| confidence_of(other, key) | float 0..1 | 证据量置信度（0 证据=0；1 条≈0.4；3 条≈0.78；6+≈1） | 否 | YES |
| last_evidence_tick(other, key) | int | 最近证据 tick（新鲜度） | 否 | YES |
| last_seen_of(other) | Dict{tile, tick} | 我最后在哪看到谁（可过时） | 否 | YES |
| model_of(other) | Dict | 含 has_food/generous/reliable 传统三槽 | 是 | YES |
| mean_prediction_error() | float | 心智模型预测误差（准不准） | 否 | YES |
| subjects_with_evidence(key) | Array | 按谓词查 subjects（P7.2B） | 否 | YES |

holder evidence predicate：`possession_predicate(item)` = `"has_item:" + item_id`（P7.2B；
报告证据经 add_reported_evidence 写入同一谓词空间，observed/received 双时间防洗白）。
证据明细列表（evidence_pos/neg）为内部结构，无公开读取 API → 见 GAPS（tom_evidence_list）。

## 8. island_sim.relationships → RelationshipStore（OBJECTIVE 关系边）

get_trust(from,to)（综合，四维加权派生）；get_dim(from,to, dim) ∈ {benevolence,
reliability, obligation, fear}，int -1000..1000。**有向**。R1 已正确分层展示。

## 9. island_sim.obligations（OBJECTIVE 承诺台账）

Array[record]；record 真实字段（commitment_contract.make）：`commitment_id, debtor_id,
creditor_id, object_id, quantity, status(PENDING_ACTIVATION/ACTIVE/FULFILLED/VIOLATED/CANCELLED),
created_tick, activated_tick, due_tick, terminal_tick, source_kind, source_request_id, terms,
history[]` + 兼容字段 debtor/creditor/object/made_tick/repaid。可只读过滤
debtor_id==selected 或 creditor_id==selected。

## 10. island_sim.agency_information_goal(actor_id)（OBJECTIVE 调用入口 / SUBJECTIVE 数据）

公开方法（island_simulation.gd:576）→ tracker.current_goal：FIND_HOLDER/UNKNOWN_SOURCE
目标的当前状态。**R1 勘察更正**：goal 生命周期字段是 **`state`**（STATE_ACTIVE 等），
不是 status——InformationSubgoalTracker 全部读 `goal.get("state", ...)`。
**这是 holder goal 当前状态的合法公开读取路径**（不读 _information_tracker_state 本体）；
UI-R2 R1 起作为 LIVE goal 正式接入（决策时刻快照另走 trace.agency_information.goal）。

## 10a. island_sim.agency_plan_run(actor_id)（OBJECTIVE 调用入口 / SUBJECTIVE 数据）

公开方法（island_simulation.gd:608）→ `_plan_tracker.runs.get(actor_id, {}).duplicate(true)`：
当前 PlanExecution run 的完整快照——`{run_id, actor_id, plan_id, root_goal, plan_snapshot,
steps[], current_step_id, state(ACTIVE/SUSPENDED/终态), started_tick, last_progress_tick,
reason_code, ...}`。UI-R2 R1 起作为 LIVE run 正式接入（计划页）；**run.steps 不保存每步
独立终态**，故非 current 步骤 UI 标 UNKNOWN（残余缺口 GAP-1a）。

## 11. island_sim.events（OBJECTIVE 事件流）

`{seq, tick, day, type, actor_id, text, ...payload}`；社交流派生只扫尾部 ≤300 条。
**R1 勘察更正（真实事件命名）**：material/commitment 系为全大写
`MATERIAL_REQUEST_* / MATERIAL_COUNTER_* / COMMITMENT_*`；P7.0/P7.2B 信息事件为
**全小写** `holder_information_shared / _refused / _stale / _unknown / _self_absent /
_missed / _requested` 与 `source_information_*`。不存在大写 INFORMATION_*/HOLDER_* 事件。
参与方字段（相关性判定）：`actor_id`（_emit 主角）、material 系 `requester_id/target_id`、
commitment 系 `debtor_id/to_id(=creditor)`、holder 系 `actor_id(=回答者)/to_id(=询问者)/
reporter_id`；`reported_holder_id` 是被谈论者，**不算直接参与**。

## 12. 明确的私有禁区（不读）

`_plan_tracker` / `_information_tracker_state` / `_material_request_runtime` /
`_commitment_runtime` / 任何 `_private`。当前信息目标与执行留痕经公开方法
`agency_information_goal` / `agency_plan_run` + `last_decision_trace` 覆盖；其余缺口登记 GAPS。

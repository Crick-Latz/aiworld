# UI-R2 ViewModel Gaps（UI_VIEWMODEL_GAP 登记）

按任务书 §66：发现 gap 不擅自给 simulation 加 accessor，登记待 GPT 决策。
基线：main 21236b1 + UI-R2 本地分支。数据来源勘察见 `UI_R2_DATA_INVENTORY.md`。

## GAP-1: active_plan_steps（计划完整步骤树）

- desired field: 当前 PlanExecution run 的全部步骤及各自状态（DONE/ACTIVE/BLOCKED/…）
- current public source: `last_decision_trace.agency_execution`（仅含**当前匹配的** step_id /
  blocker_reason / candidate_keys，是单步留痕，不是步骤树）
- missing information: 其余步骤的存在、顺序与状态；run 整体进度
- recommended future read-only API: `sim.plan_execution_snapshot(actor_id) -> {run_id, plan_id, steps:[{step_id,desc,status}]}`（或把步骤快照写进 decision trace）
- blocking UI feature: 计划页目前只能渲染"当前步 + 阻塞"链（已实现），无法显示完整计划流与已完成步骤

## GAP-2: active_material_requests（当前请求快照）

- desired field: 选中角色相关的当前 MATERIAL_REQUEST 状态（ACTIVE/OFFERED/…、对象、数量、对方）
- current public source: 仅 `island_sim.events` 尾部派生（MATERIAL_REQUEST_* 事件流）
- missing information: 请求的**当前**状态（事件只能推断历史，终态可能已变化）
- recommended future read-only API: `sim.material_request_snapshot(actor_id) -> Array`
- blocking UI feature: 社会页"最近物资请求"只能显示事件文本（已实现并标注派生），无法显示实时状态徽章

## GAP-3: active_information_goal 直读（holder goal 全量字段）

- desired field: FIND_HOLDER 目标的完整生命周期字段（goal_id/parent 三元组/重试计数等）
- current public source: `sim.agency_information_goal(actor_id)`（公开方法，**已可用**）+
  `last_decision_trace.agency_information.goal`（决策时刻快照）
- missing information: 非决策时刻的实时 goal 状态（agency_information_goal 已覆盖大部分；
  该 gap 仅指"与决策解耦的连续状态流"）
- recommended future read-only API: 已存在（agency_information_goal）；如需历史轨迹可加
  `information_goal_history(actor_id)`
- blocking UI feature: 无阻断——社会页已用事件流 + 决策留痕双源渲染；实时状态可再接

## GAP-4: tom_evidence_list（ToM 证据明细）

- desired field: 每条信念的 evidence_pos/evidence_neg 明细（event_id/tick/kind）
- current public source: `confidence_of` / `last_evidence_tick`（聚合值，公开）；
  明细列表为 `_entry` 内部结构，无公开读取方法
- missing information: "这条判断是从哪几个事件来的"逐条追溯
- recommended future read-only API: `tom.evidence_of(other_id, key) -> Array[Dictionary]`
- blocking UI feature: 认知页目前显示置信度与最近证据 tick（已实现），无法点开看证据链

## GAP-5: memory.importance（模拟侧原生重要度）

- desired field: 记忆的模拟侧重要度
- current public source: 无；UI 用 `derived_importance = abs(appraisal_goal_congruence)`
  作为 presentation heuristic（HUD 已标 [推导]）
- missing information: 模拟自身是否有重要度语义（当前判定：无独立字段）
- recommended future read-only API: 若认知线认为 appraisal 即语义，可不改；
  若需要独立重要度应由模拟显式存储
- blocking UI feature: 无阻断（已按 derived 标注）

## GAP-6: relationship_change_trajectory（关系变化轨迹）

- desired field: 每条关系边的近期变化记录（何时 +N/-N、来源事件）
- current public source: `last_decision_trace.belief_change`（单次决策快照）；
  RelationshipStore 只存当前值
- missing information: 历史轨迹
- recommended future read-only API: relationship delta 事件化或 `relationships.history(a,b)`
- blocking UI feature: 关系页"关系变化"目前显示占位"—（暂无轨迹数据）"或事件派生文本

## 非缺口澄清（任务书怀疑、勘察确认可用）

- **decision_candidates**：runtime 真实存在（`last_decision_trace.top_candidates`，softmax
  输入的候选效用表）——Decision 页候选排序为真实数据非 mock；仅当某 tick 无决策留痕时为空
  （HUD 显示 gap 提示文案）。
- **agency_execution 当前步骤/阻塞**：真实存在于 trace（P6.3B-1 §八留痕）——计划页数据合法。

# UI-R2 ViewModel Gaps（UI_VIEWMODEL_GAP 登记）

按任务书 §66：发现 gap 不擅自给 simulation 加 accessor，登记待 GPT 决策。
基线：main 21236b1 + UI-R2 本地分支。数据来源勘察见 `UI_R2_DATA_INVENTORY.md`。
**R1 Semantic Hardening 修订（2026-09-15）**：GAP-3 关闭；GAP-1 按复审意见更名收窄
（`agency_plan_run` 公开 run accessor 实际存在，原表述"没有公开 run accessor"不成立）。
当前 gap 数：**5**（GAP-1a/2/4/5/6）。

## GAP-1a: per_step_terminal_status_history（每步终态历史）

- desired field: run 内每个 step 的独立完成/失败历史
- current public source: `sim.agency_plan_run(actor_id)`（公开只读，返回 duplicate）——
  含 run_id/plan_id/root_goal/plan_snapshot/steps/current_step_id/state/reason_code/
  started_tick/last_progress_tick。UI-R2 R1 起计划页已用它渲染 LIVE run
  （steps 顺序 + current 标记 + run state；无法证明的步骤标 UNKNOWN，不虚构 COMPLETED）
- missing information: run.steps 不保存每个步骤的独立终态（DONE/FAILED 逐条历史）
- recommended future read-only API: tracker 若已有步骤级 trace 可暴露
  `sim.agency_plan_step_history(actor_id) -> Array[{step_id, from, to, tick}]`
- blocking UI feature: 计划页无法显示"哪些步骤已完成"——只能标 CURRENT/UNKNOWN

## GAP-2: active_material_requests（当前请求快照）

- desired field: 选中角色相关的当前 MATERIAL_REQUEST 状态（ACTIVE/OFFERED/…、对象、数量、对方）
- current public source: 仅 `island_sim.events` 尾部派生（MATERIAL_REQUEST_* 事件流，
  R1 起只收选中 NPC 直接参与的事件）
- missing information: 请求的**当前**状态（事件只能推断历史，终态可能已变化）
- recommended future read-only API: `sim.material_request_snapshot(actor_id) -> Array`
- blocking UI feature: 社会页"最近物资请求"只能显示事件文本（已实现并标注派生），无法显示实时状态徽章

## ~~GAP-3: active_information_goal 直读~~（已关闭）

- 关闭原因：公开只读 accessor `sim.agency_information_goal(actor_id)` 已存在且被 UI-R2 R1
  起正式使用（live goal；goal 生命周期字段为 `state`）。决策时刻快照走
  `last_decision_trace.agency_information.goal`，两时间语义已分离。
  若未来需要 goal 历史轨迹，另立新 gap（information_goal_history），不算本 gap 延续。

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
- **agency_plan_run / agency_information_goal**：公开只读 accessor（island_simulation.gd
  576/608 行），R1 起 ViewModel 合法调用（测试锁定 live_plan_uses_public_agency_plan_run /
  live_information_goal_uses_public_accessor）。

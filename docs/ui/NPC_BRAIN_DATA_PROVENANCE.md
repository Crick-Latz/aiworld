# NPC Brain Data Provenance（UI-R2）

每个 UI 字段的数据来源与三层标记：**objective（世界事实/权威状态）**、
**subjective（NPC 主观）**、**derived（presentation 推导）**。
HUD 用颜色徽章渲染：[事实]=金 / [主观]=蓝 / [推导]=灰。真实 schema 依据
`UI_R2_DATA_INVENTORY.md`（编码前实码勘察，非任务书推断）。

## selected_actor（schema 0.3，由 NpcBrainViewModel.build 组装）

| UI field | source | scope | authoritative | subjective | derived |
|---|---|---|---|---|---|
| identity.name/status/location | actor.display_name/activity/tile | objective | yes | — | — |
| state.inventory_items | actor.inventory | objective | yes | — | — |
| needs.hunger/thirst/social | actor.needs（越高越急） | objective | yes | — | — |
| needs.fatigue | 1000 - actor.needs.energy | derived（显式换算标注） | — | — | yes |
| needs 排序 | 按 frac 降序 | derived（展示排序） | — | — | yes |
| emotions.rows / dominant | actor.personality.emotions（signed -1..1） | subjective | — | yes | dominant 为展示聚合 |
| personality.traits | actor.personality.traits（0..1） | objective（人格参数） | yes | — | — |
| personality.beliefs | actor.personality.beliefs{text:{weight}} | subjective | — | yes | — |
| decision.chosen/reason | last_decision_trace.selected/reason | subjective | — | yes | — |
| decision.candidates | last_decision_trace.top_candidates（真实 softmax 效用） | subjective | — | yes | 排序为展示 |
| decision.current_action | actor.activity | objective | yes | — | — |
| decision.blocker | trace.agency_execution.blocker_reason | subjective | — | yes | — |
| decision.next_step | intentions.current_intention | subjective | — | yes | — |
| decision.dominant_interpretation | trace.candidate_interpretations | subjective | — | yes | — |
| plan.goal | trace.active_goal/goal_desc（enrich） | subjective | — | yes | — |
| plan.intention | intentions.current_intention | subjective | — | yes | — |
| plan.execution / decision_snapshot | trace.agency_execution（决策时单步留痕快照） | subjective | — | yes | 状态图标为展示 |
| plan.live（root_goal/run/steps/attached_information_goal） | sim.agency_plan_run + sim.agency_information_goal（公开只读） | subjective（actor 的计划，引擎簿记） | yes（run 本体） | — | LIVE 区 root goal 只来自 live_run.root_goal；信息目标仅在 parent_run_id==run_id（blocker_step_id 存在时==current_step_id）时附着；steps 非当前步标 UNKNOWN（GAP-1a） |
| plan.live_information_goal（section=live_info） | sim.agency_information_goal（公开只读；字段 **state**） | subjective | yes | — | 当前 live 信息目标三态：attached-to-live-run / independent-live-info（无 run 或身份不匹配，no_arrow_in 独立区「当前信息目标 LIVE」）/ absent；**LIVE accessor 数据绝不进 snapshot 区**（不变量由测试锁定）；决策时刻目标另存 decision_snapshot.information_goal（仅 snapshot 区） |
| mind.open_questions | actor.open_questions{about,kind,entropy,stakes,tick} | subjective | — | yes | — |
| mind.primary_question | open_questions 按 stakes 降序→tick 降序选出的当前最重要问题 | derived（选择为聚合） | — | — | yes |
| emotions.rows | personality.emotions 原始值 | subjective | — | yes | — |
| emotions.dominant | max(abs(value)) 聚合选择 | derived（HUD 主导情绪徽章） | — | — | yes |
| mind.tom_subjects[].rows.value | tom.snapshot()/belief_about（动态谓词含 has_item:*） | subjective | — | yes | — |
| mind.tom_subjects[].rows.confidence | tom.confidence_of | subjective | — | yes | — |
| mind.tom_subjects[].rows.last_evidence_tick | tom.last_evidence_tick | subjective | — | yes | — |
| mind.tom_subjects[].last_seen | tom.last_seen_of（可能过时，HUD 标注） | subjective | — | yes | — |
| mind.prediction_error | tom.mean_prediction_error | subjective | — | yes | — |
| relationships.rows.trust | relationships.get_trust（四维加权综合） | objective | yes（边本身） | — | trust 为模拟侧派生值，UI 原样显示 |
| relationships.rows.benevolence/reliability/obligation/fear | relationships.get_dim | objective | yes | — | — |
| relationships.rows.tom | tom.model_of 三槽 | subjective | — | yes | — |
| memories.rows.{seq,tick,text,type,counterpart} | actor.memories（真实字段，≤20） | subjective | — | yes | — |
| memories.rows.day | tick/24+1 | derived（显式标注） | — | — | yes |
| memories.rows.derived_importance | abs(appraisal_goal_congruence) | derived（HUD 标注，非模拟字段→GAP-5） | — | — | yes |
| social.commitments | island_sim.obligations 只读过滤（debtor/creditor==selected） | objective | yes | — | 过滤为展示 |
| social.recent_requests / holder_events / source_information_events / recent_social_events | island_sim.events 尾部 ≤300 扫描派生，**仅收选中 NPC 直接参与的事件**（_event_relevant_to_actor：actor_id/requester_id/target_id/to_id/debtor_id/creditor_id/reporter_id/actor_ids 命中；reported_holder_id 不算参与）；holder（谁持有 X）与 source（哪里有 X）**分桶** | objective（事件流为事实） | yes | — | 分组/截断/相关性过滤为展示 |
| why | {provenance: derived, decision_reason, nodes[], links[], context[]}——节点只来自 trace/live/公开状态；**节点间箭头全部为 presentation 自建 [推导] PRESENTATION_LINK**（节点同屏存在不构成记录级因果证据；显式因果字段出现前不升级记录级边）；trace.reason 保持 [主观]；需求/情绪只进 context（无箭头） | 整体 derived；节点各随其源；链接一律 derived | — | — | 串联本身 derived；无 LLM |

## 硬规则落点

1. 真实库存（Overview，[事实]）与 ToM 对他人库存的判断（认知页，[主观]）物理分区，
   永不同区显示（BRAIN_TRUTH_VS_SUBJECTIVE fixture + brain-subjective-vs-truth 截图为验收）。
2. 主观区域绝不显示对方真实 inventory/坐标——last_seen 显示"我最后看到的（可能过时）"。
3. derived_importance / fatigue / day / dominant 情绪选择 / primary_question 选择 /
   why 串联等 presentation 换算或聚合一律 [推导] 徽章 + 注释说明。
4. why 每节点/链接带 provenance + source_kind + source_ref；确定性生成，不调用 LLM；
   无 delta/trend 数据禁止"升高/下降"措辞；无证据的 need→action 关联不画箭头（fail-closed）。
5. 事件相关性：无关两人之间的请求/情报事件不得进入选中 NPC 的社会页；
   被谈论者（reported_holder_id）不算事件参与方。

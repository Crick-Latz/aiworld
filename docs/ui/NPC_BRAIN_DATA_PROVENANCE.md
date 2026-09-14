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
| plan.execution / nodes | trace.agency_execution（单步留痕，非步骤树→GAP-1） | subjective | — | yes | 状态图标为展示 |
| mind.open_questions | actor.open_questions{about,kind,entropy,stakes,tick} | subjective | — | yes | — |
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
| social.recent_requests / holder_events / recent_social_events | island_sim.events 尾部 ≤300 扫描派生 | objective（事件流为事实） | yes | — | 分组/截断为展示 |
| why_chain | presentation 串联真实节点（needs/trace/intention/activity） | mixed | 节点各随其源 | 节点各随其源 | 串联本身 derived；无 LLM |

## 硬规则落点

1. 真实库存（Overview，[事实]）与 ToM 对他人库存的判断（认知页，[主观]）物理分区，
   永不同区显示（BRAIN_TRUTH_VS_SUBJECTIVE fixture + brain-subjective-vs-truth 截图为验收）。
2. 主观区域绝不显示对方真实 inventory/坐标——last_seen 显示"我最后看到的（可能过时）"。
3. derived_importance / fatigue / day 等 presentation 换算一律 [推导] 徽章 + 注释说明公式。
4. why_chain 每节点带 provenance + source_kind + source_ref；确定性生成，不调用 LLM。

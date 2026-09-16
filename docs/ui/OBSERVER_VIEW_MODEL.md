# Observer ViewModel（UI-R1）

观察界面的唯一数据契约：`observer_main`（presentation adapter）组装一个 `Dictionary` model，
HUD 组件只实现 `render(model: Dictionary)`（或组件级 render 子调用）。HUD 不读取
`island_sim` / `actor` / request tracker / commitments / 任何模拟内部对象。

- 契约版本：`view_schema_version = "0.3"`（UI-R2 七页大脑观察器；组装下沉 NpcBrainViewModel；0.2/0.1 为历史）
- 文档分层：**CURRENT**（已组装并渲染）/ **OPTIONAL**（HUD 已渲染、模拟侧数据可能为空）/ **PLANNED**（壳已留、字段尚不存在）

## 顶层字段

| 字段 | 类型 | 状态 | 说明 |
|---|---|---|---|
| `view_schema_version` | String | CURRENT | 契约版本号 |
| `state_revision` | int | CURRENT | island：sim tick；演示模式 0 |
| `world_name` | String | CURRENT | 顶栏世界名（荒岛 · 观察模式 / 灰雾港 · 故事模式 / 巡航模式） |
| `time_label` | String | CURRENT | 顶栏时间文本 |
| `paused` | bool | CURRENT | 顶栏"已暂停/运行中" |
| `speed_multiplier` | int | CURRENT | 顶栏 "N×"（1/2/4） |
| `lag_ticks` | int | CURRENT | 顶栏滞后提示（>0 显示） |
| `warning_text` | String | CURRENT | 非空时顶栏橙色 ⚠ 提示（截断 44 字符） |
| `hint_text` | String | OPTIONAL | 覆盖操作提示文本；缺省用场景默认 |
| `recent_events` | Array | CURRENT | 底部事件页：`{seq, text, cause_seq?, actor_ids?, day?}` 最近 100 条 |
| `causal_chains` | Array | CURRENT | 底部因果链页：`{title, steps:[String]}`，由 `cause_seq` 派生（最多 4 链） |
| `story_threads` | Array | OPTIONAL | 底部故事页：ThreadEngine 线程（每 30 tick 组装一次） |
| `narrative_sentences` | Array | OPTIONAL | 故事页兜底：句子级编年史 |
| `dialogue_transcript` | Array | OPTIONAL | 底部对话页：`{day, speaker, text, act, seq}` |
| `chronicle_text` | String | OPTIONAL | 事件页头部金色编年史（bbcode） |
| `world_facts_text` | String | OPTIONAL | 故事模式灯塔状态等（保留旧字段） |
| `narrative_ir_claims` | Array | OPTIONAL | 叙事 IR claims（暂无 UI 消费） |

## selected_actor（右侧 NPC Inspector，UI-R2 七页：概览/决策/计划/认知/关系/记忆/社会）

由 `game/src/presentation/npc_brain_view_model.gd::NpcBrainViewModel.build(sim, actor_id)`
只读组装（observer_main 只调用不组装）。每个数据块带 `provenance`
（objective/subjective/derived，HUD 渲染 [事实]/[主观]/[推导] 徽章）。
字段级 provenance 详表见 `NPC_BRAIN_DATA_PROVENANCE.md`；真实 schema 依据
`UI_R2_DATA_INVENTORY.md`。

### CURRENT（runtime 真实产出）

| 字段 | 说明 |
|---|---|
| id / display_name / status_text / location_text | 身份（objective） |
| state.activity / state.inventory_items[{id,count,provenance}] | 客观状态 |
| needs.rows[{key,label,value,frac,provenance}] ×4 | hunger/thirst/social(objective) + **fatigue=1000-energy(derived，显式标注)**；按紧迫度降序 |
| emotions.rows[{key,label,value}]×5 / emotions.dominant | signed -1..1 + 主导情绪聚合 |
| personality.traits[{key,label,value}]×10 / personality.beliefs[{text,weight}] | 0..1 特质 / 信念（weight 真实 schema） |
| decision.{chosen,reason,current_action,blocker,next_step,considered_count,dominant_interpretation,decision_tick} | 决策留痕（subjective；current_action 为 objective） |
| decision.candidates[{action,utility,chosen}] | **真实 softmax 候选效用表**（trace.top_candidates；无决策 tick 时为空） |
| plan.nodes[{kind,label,value,status,source_kind,section,no_arrow_in?}] | 计划状态分区（R1.1/R1.2）：section=live（当前执行 LIVE，root goal 只来自 live_run.root_goal，trace.goal_desc 禁入）/live_info（当前信息目标 LIVE——无 run 可附着或身份不匹配的当前 live 信息目标，no_arrow_in，**LIVE accessor 数据绝不落入 snapshot**）/snapshot（上次决策快照）；live 信息目标仅 parent_run_id==run_id（blocker_step_id 存在时还需==current_step_id）时附着 run 流。当前信息目标三态：attached-to-live-run / independent-live-info / absent；决策时刻信息目标永远只在 snapshot |
| plan.live{root_goal,run{run_id,plan_id,state,reason_code,current_step_id},steps[],attached_information_goal?}（兼容平铺键 live_run） | **LIVE**：`sim.agency_plan_run(actor_id)` 公开只读 accessor（他现在正在执行什么） |
| plan.live_information_goal / plan.decision_snapshot | LIVE 信息目标（`sim.agency_information_goal`，字段 **state**）与决策时刻快照（trace.agency_execution / trace.agency_information.goal）两时间语义分离 |
| mind.open_questions[{about_name,kind,entropy,stakes,tick,source_event_ids}] | 未解之问 |
| mind.primary_question{...} | 按 stakes 降序→tick 降序选出的当前最重要问题（选择为 derived） |
| mind.tom_subjects[{other_name,rows[{predicate,label,value,confidence,last_evidence_tick}],last_seen}] | **动态谓词知识**（has_item:* 任意谓词，含 P7.2B holder evidence） |
| mind.prediction_error | 心智模型预测误差 |
| relationships.rows[{other_name,trust,benevolence,reliability,obligation,fear,change?,tom}] | 真实有向边（objective）+ ToM 三槽（subjective）两层分离 |
| memories.rows[{seq,tick,day,text,type,counterpart,derived_importance,interpretation}] | 记忆卡片（day/derived_importance 为 derived） |
| social.commitments[{direction,counterpart_name,object,quantity,status,due_tick,source_request_id}] | 承诺台账只读过滤（我欠/欠我） |
| social.recent_requests / holder_events / source_information_events / recent_social_events | 事件尾部派生（≤300 扫描；**仅选中 NPC 直接参与的事件**）；holder_information_*（谁持有 X）与 source_information_*（哪里有 X）**分桶显示** |
| why{provenance:derived, decision_reason, nodes[], links[], context[]} | **fail-closed 因果链**（无 LLM）：决策理由（trace.reason，[主观]）优先；**节点间箭头全部为 presentation 自建 [推导] PRESENTATION_LINK**（节点同屏存在不构成记录级因果证据）；需求/情绪只进 context（无箭头）；无 delta 数据禁止"升高"措辞 |
| 兼容字段 activity_text/goal_text/inventory_text/needs_text/decision_text/inventory_items | 0.2 兼容（wander/story 模式） |

### DERIVED（presentation 推导，UI 显式标注）

fatigue（=1000-energy）、needs 排序、emotions.dominant（max(|value|) 聚合选择）、
memories.day（=tick/24+1）、memories.derived_importance（=abs(appraisal_goal_congruence)）、
mind.primary_question（stakes/tick 排序选择）、social 各事件分组与相关性过滤、
why 的串联本身（含 links）。

### PLANNED（等模拟线 read-only API，见 UI_R2_VIEWMODEL_GAPS.md）

per_step_terminal_status_history（GAP-1a）、active_material_requests（请求实时状态，
GAP-2）、tom_evidence_of（证据明细，GAP-4）、relationship history（GAP-6）、
memory 原生 importance（GAP-5）。
~~active_information_goal 直读~~（GAP-3 已关闭：公开 accessor
`agency_information_goal` 存在并被使用）。

### PLANNED（Inspector 壳已留、字段尚不存在）

| 计划字段 | 说明 | 缺失原因 |
|---|---|---|
| `selected_actor.memory_items[].source_event_ids` | 记忆 → 事件溯源下钻 | 认知层记忆未带稳定事件引用（仅 seq） |
| `selected_actor.personality.temperament` | 气质独立数据源 | UI 已按三组展示（基础特质/气质与风险偏好/社交倾向），数据仍来自同一 traits 表 |
| `selected_actor.personality.social_tendencies` | 社交倾向独立分组 | 同上（暂以共情/社交/利他三项近似） |
| `selected_actor.decision.blocker`（结构化） | 当前为文本"无"/描述 | P6 blocker 结构未暴露到 trace |
| `selected_actor.relationship_rows[].last_interaction` | 最近互动事件 | RelationshipStore 无时间索引 |
| `selected_actor.plans[].steps[].state` | 多步计划逐格状态 | 计划步执行状态在 Registry，未投影 |
| `selected_actor.history_rows[].witnesses` | 谁目击了该事件 | 事件目击者推断未持久化 |

## 装配与隔离规则

1. model 的唯一组装点：`game/scenes/observer/observer_main.gd::_refresh_hud()`（island 分支）
   与 `game/scenes/ui/ui_preview.gd::fixture_model()`（离线夹具）。
2. HUD/Inspector/时间线组件只消费 Dictionary；新增字段不得要求 HUD 访问模拟对象。
3. 旧字段（`activity_text` / `inventory_text`）保留为 0.1 兼容；演示模式（wander/story）
   仍走旧字段路径。
4. 缺失可选字段一律渲染占位文案（"暂无数据"/"—"），不抛错。

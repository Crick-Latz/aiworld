# Observer ViewModel（UI-R1）

观察界面的唯一数据契约：`observer_main`（presentation adapter）组装一个 `Dictionary` model，
HUD 组件只实现 `render(model: Dictionary)`（或组件级 render 子调用）。HUD 不读取
`island_sim` / `actor` / request tracker / commitments / 任何模拟内部对象。

- 契约版本：`view_schema_version = "0.2"`（UI-R1 v2；Inspector 6 页制；0.1 为旧 3D HUD）
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

## selected_actor（右侧 NPC Inspector）

未选中时为 `null`，Inspector 显示"未选中 · 点击世界中的角色"占位。

| 字段 | 类型 | 状态 | Inspector 位置 |
|---|---|---|---|
| `id` | String | CURRENT | — |
| `display_name` | String | CURRENT | 头部名字 |
| `status_text` | String | CURRENT | 头部状态小字（缺省回退 `activity_text`） |
| `activity_text` | String | CURRENT | 0.1 兼容字段 |
| `goal_text` | String | CURRENT | 概览·目标 |
| `decision_text` | String | CURRENT | 概览·决策（= decision.reason 摘要） |
| `location_text` | String | CURRENT | 概览·位置（逻辑格） |
| `needs_text` | String | CURRENT | 概览·需求（饿/渴/累/孤独） |
| `inventory_text` | String | CURRENT | 0.1 兼容字段 |
| `inventory_items` | Array | CURRENT | 概览·物资：`{id, count}` |
| `memory_items` | Array | CURRENT | 记忆页：`{day, tick, text, type, counterpart, importance}`（最近 ≤20） |
| `personality.traits` | Array | CURRENT | 性格页·特质：`{key, label, value}`（10 项，中文标签） |
| `personality.emotions` | Array | CURRENT | 性格页·情绪：`{key, value}`（|v|>0.05 才出现） |
| `personality.beliefs` | Array | CURRENT | 性格页·信念：`{text, weight}` |
| `decision` | Dictionary | CURRENT | 决策页：`{plan, step, reason, blocker, next_step}` |
| `relationship_rows` | Array | CURRENT | 关系页（两层分离）：真实关系边 `{other_id, other_name, trust(综合), benevolence, reliability, obligation, fear, change}`（get_dim 四维）+ 主观判断 `tom:{has_food,generous,reliable}`——ToM 信念 ≠ 关系边，UI 分区展示 |
| `history_rows` | Array | CURRENT | 历史页·最近事件：`{day, seq, text}`（该角色相关事件，倒序 ≤12） |
| `history_dialogue_rows` | Array | CURRENT | 历史页·最近对话：该角色台词（≤6 条回溯） |
| `history_chain_rows` | Array | CURRENT | 历史页·行动链：该角色自身 cause_seq 链步（无则空→占位） |

### PLANNED（Inspector 壳已留、字段尚不存在）

| 计划字段 | 说明 | 缺失原因 |
|---|---|---|
| `selected_actor.memory_items[].source_event_ids` | 记忆 → 事件溯源下钻 | 认知层记忆未带稳定事件引用（仅 seq） |
| `selected_actor.personality.temperament` | 气质独立数据源 | UI 已按三组展示（基础特质/气质与风险偏好/社交倾向），数据仍来自同一 traits 表 |
| `selected_actor.personality.social_tendencies` | 社交倾向独立分组 | 同上（暂以共情/社交/利他三项近似） |
| `selected_actor.decision.candidates` | 决策候选与打分（决策可解释性） | decision trace 无候选列表，仅 reason |
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

# P6.0 — World Knowledge & Agency Foundation 报告（给 GPT）

日期：2026-09-07 · 执行：GLM · 前置：P4.3 CLOSED / P5 CLOSED（K1）
严格回归：**21 套件 / 610 断言 PASS**（新增 p6_world_knowledge 15 Gate）
**全部合成 fixture 验证——未动任何现有层**（认知/决策/模拟/ThreadEngine/经济零改动）。

## 核心链路（§0 宪法落地）

```text
Knowledge proposes possibilities; Planner constructs means;
DecisionEngine chooses; World rules execute.
（知识提议可能；规划器构造手段；决策引擎选择；世界规则执行）
```

"我有一个问题" → "周围这些东西可以怎么利用，我缺什么条件，我能不能创造这些条件"：

```text
Problem（HUNGER/ESCAPE_DESIRE/...13 种）
→ Knowledge Retrieval（WorldKnowledgeStore 按 layer 过滤）
→ Affordances（rules_producing(FOOD)：berry/animal/fish/trap）
→ Required Capability（animal→HUNT_MEDIUM）
→ Possible Means（spear affords HUNT_MEDIUM）
→ Missing Preconditions（SHARP_STONE 未知 → 具名阻塞）
→ Subgoals（寻找 SHARP_STONE）或 Social（向伙伴求助候选）
→ PlanProposal[]（READY / BLOCKED_PLAN）
→ [下一阶段] 交回现有 DecisionEngine 选择
```

## 模块清单（`game/src/simulation/knowledge/`，7 文件）

| 文件 | 职责 |
|---|---|
| `capability_spec.gd` | 24 能力 × 9 域（CRAFT/HUNT/CONSTRUCTION/...）——能力≠行动，CUT 可由刀/利石/斧提供 |
| `problem_spec.gd` | 13 问题 → satisfied_by 资源标签。**不替换 Need/Goal**（P1 冻结）——是知识检索的查询语义 |
| `knowledge_fact.gd` | 四层知识（COMMON_HUMAN/CULTURAL/EXPERTISE；LEARNED_LOCAL 留给既有 Belief/Spatial，不复制） |
| `affordance_rule.gd` | 一物多用规则（wood→燃料/结构/造矛/造筏/庇护所） |
| `world_knowledge_store.gd` | 规则库 + available_for(actor) 按专长过滤 + 三类检索 |
| `knowledge_pack.gd` | 世界包装载器（common_human.json + island_survival.json；未来只换包不换脑子） |
| `means_ends_planner.gd` | 递归手段-目的规划（MAX_DEPTH=3/MAX_BRANCHES=5）+ AgencyTrace |

**材料语义约定**：`subject_tags` = 全所需（AND）；备选料用多条规则表达（bind_cord 用 BINDING，VINE/ROPE 留作未来包扩展）。

## 数据包（`game/data/knowledge/`）

- `common_human.json`：10 facts + 9 affordances（水能喝/动物肉能吃/锋利能切/火会烧/**枪能威胁但知识≠持有**）
- `island_survival.json`：9 facts + 6 affordances（矛配方/生火/筏概念/陷阱=EXPERTISE/捆扎/庇护所）——boat_concept 知识存在但世界无船，planner 只在材料+能力齐时给 READY

## 三个关键设计裁定（本轮实证）

1. **知识≠信念≠持有（§13）**：`know(Gun→Threaten)` 常识在库里，但 ctx 无 GUN 时 gun_threaten 规则不进候选（KB 门）——planner 只看主观 ctx（possessed/known_source/known_peers），**结构上不读世界**。
2. **缺料具名阻塞而非静默**（§20）：工具在知识中存在但材料未知 → BLOCKED_PLAN + missing=[SHARP_STONE] + SUBGOAL"寻找 SHARP_STONE"——不凭空 craft，且给出下一步探索目标（与 P5 绝望搜索的天然接口，P6.2 接线）。
3. **求助候选保留 missing**（§22）：缺 NAVIGATE + 伙伴有航行专长 → 加 REQUEST_HELP 步骤但 missing 不移除——单人视角仍缺，合作是候选不是强制。

## AgencyTrace（§27）

结构化留痕（非 CoT）：problem → retrieved_knowledge → considered_capabilities → candidate_means → missing_requirements → generated_plan_ids。"为什么 NPC 想到了造长矛"可答：hunger → animal affords food → hunting required → spear provides hunting → 材料已知——**不是 LLM 事后编理由**。trace 门已锁（HUNGER 场景留痕含知识引用）。

## 测试（KA-KO 15/15 + trace，全部合成 fixture）

| 门 | 验证 | 结果 |
|---|---|---|
| KA | 包装载（19 facts/15 affordances） | ✅ |
| KB | 知道枪能威胁但无枪 → 无用枪计划 | ✅ |
| KC | ctx 无 WOOD → 无 CRAFT；有 → 有（隐藏物隔离——planner 不读世界，结构保证） | ✅ |
| KD | 能力检索（SHARP_STONE→CUT） | ✅ |
| KE | WOOD ≥4 种 affordance | ✅ |
| KF | 专长只影响 confidence/cost 估计，不改规则集 | ✅ |
| KG/PA | 饿+已知浆果 → 直接 forage，不找隐藏资源 | ✅ |
| KH/PB | 饿+见动物+材料齐 → CRAFT bind_cord/spear → HUNT → FOOD 全链 READY | ✅ |
| KI/PC | 缺 SHARP 材料 → BLOCKED + missing=[SHARP_STONE] + 无凭空 craft | ✅ |
| KJ/PD | 离岛 → 筏需 NAVIGATE/BUILD_STRONG 具名缺失 | ✅ |
| KK | 缺能力+伙伴有专长 → REQUEST_HELP 候选（不强制） | ✅ |
| KL | A 知陷阱术 B 不知 → 同世界不同候选集 | ✅ |
| KM | 同输入双跑 JSON 全同 | ✅ |
| KN | ctx/store 输入前后逐位一致 | ✅ |
| KO | 真 sim 派生 ctx 跑 planner：模拟 hash 不变 + 提案无执行钩子 | ✅ |

## 行为挖掘交付（§4-7/§33）

- [p6_narrative_behavior_mining.md](../design/p6_behavior_mining/p6_narrative_behavior_mining.md)：20 部 × 13 元组案例 + 6 条跨案例模式，SOURCE_DERIVED / ENGINEERING_INFERENCE / NOT_IMPLEMENTED 三级标记
- [p6_behavior_pattern_library.md](../design/p6_behavior_mining/p6_behavior_pattern_library.md)：23 问题域模式库 + 4 条跨域涌现模式
- 关键叙事发现 `[S]`：单人长期生存仅 4/20 且高心理代价——社会依赖应为一等公民（KK 门已体现）；"工具的工具"是三大荒岛经典的共同主轴（递归 planner 的叙事合法性）

## 完成门（§35）

| 门 | 状态 |
|---|---|
| Knowledge ≠ Belief ≠ Possession | ✅ KB/KB-C |
| 同世界不同知识→不同候选 | ✅ KL |
| 隐藏资源不影响计划 | ✅ KC（结构保证：planner 不读世界） |
| 工具功能数据驱动 | ✅ 全部经 affordance JSON |
| 材料多用途 | ✅ KE |
| 缺前置产生子目标 | ✅ KI（SUBGOAL 寻找 SHARP_STONE） |
| planner 不能执行 | ✅ KO（提案无钩子，纯数据步骤） |
| planner 不能改世界 | ✅ KN/KO |
| DecisionEngine 仍是选择者 | ✅（本轮未接线——planner 输出止于 PlanProposal） |
| 认知层未动 | ✅（零改动） |
| determinism | ✅ KM |
| strict regression | ✅ 21 套件 / 610 断言 |

**P6.0 = CLOSED。**

## 已知限制（诚实记录）

1. **未接线运行时**：planner 尚未接入 DecisionEngine——P6.0 按指令只验证"会想办法"的脑子本身；接线（含 belief_refs 回填、ctx 从 SpatialBelief/inventory 派生）是 P6.2 的第一件事。
2. 材料备选语义用多规则表达（AND 单料）；丰富备选（VINE/ROPE/纤维）留世界包扩展。
3. 社会路线只有 SELF/REQUEST_HELP（§23 遵守）；偷/抢/交易留 P6.7/P6.8。
4. expertise_multiplier 是线性启发（cost×0.75/conf×1.25）；真实学习曲线留 P6.2 校准。
5. LEARNED_LOCAL（这岛东北有泉）完全由既有 Belief/Spatial 承载——未在本库复制（正确），但 planner ctx 派生时要小心别把"知道类型"和"知道位置"混了（P6.2 接线时的审计点）。

## 下一步（待 GPT 指令）

按既定路线：P6.1 Generalized Affordance / Capability 深化 → P6.2 Means–Ends Planning 接线（planner→DecisionEngine，含 ctx 派生与 belief_refs）→ P6.3 物品/制作 → P6.5 扩展食物生态（接手 P5 遗留：探索彩票→真实资源主导）。

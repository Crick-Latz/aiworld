# 代码位置索引（供 GPT 评审）

仓库：`D:\Project_AI\aiword` ｜ 模拟层代码共 33 个 GDScript 文件、约 5000 行（不含测试/场景/文档）
所有路径相对 `game/`。测试 12 套 373 项全绿。

---

## 一、认知核心（P1.5 三刀所在——评审优先级最高）

| 文件 | 行数 | 职责 | 关键函数 |
|---|---|---|---|
| `src/simulation/cognition/cognitive_transition.gd` | ~470 | **统一认知入口**：主观事件→记忆检索→评价→解释竞争→信念→情绪→四维关系→社会倾向→主观记忆。所有事件状态变化必经此处，禁止旁路 | `process()`；`_appraisal_my_refusal/_appraisal_my_refusing/_appraisal_received_help`；`_update_beliefs/_update_relationships`；`_open_question`（认识问题形成）；ACQUIRE/PROMISE/REQUEST 语义分支；Brier 校准采样 |
| `src/simulation/cognition/subjective_event.gd` | ~75 | 每个观察者的主观事件（带认知快照 believed_rich/信任/自身需求/规范 + 语义 semantics + role 判定） | `build()`；`_role_of()` |
| `src/simulation/cognition/interpretation.gd` | ~130 | **解释竞争**：拒绝 5 候选/接受 4 候选（各挂动机本体标签 SELF_INTEREST/INCAPABLE/…），权重=信念×ToM×人格动力×情绪；归一化香农熵 `entropy()` | `interpret_refusal/interpret_acceptance`；`hostility_weight`；`entropy` |
| `src/simulation/cognition/personality_dynamics.gd` | ~50 | 人格控制**更新过程**而非行为倍率：背叛学习率/敌意归因偏置/情绪升降速率/反刍/承诺/规范逆反/认识驱动/不确定容忍 | `dynamics()` |
| `src/simulation/cognition/theory_of_mind.gd` | ~150 | **schema-free 心智模型**：任意谓词槽（has_food/has_water/has_spear/hungry/competence_xxx/influence_xxx），证据累积+置信度折算+可削弱（信念修正）；响应预测模型（Predict→Observe→Learn）+预测误差记录；`last_seen`（P1.7 寻人来源） | `add_evidence/weaken/belief_about/raw_belief`；`update_response/record_prediction_error`；`see_at/last_seen_of` |
| `src/simulation/cognition/belief_store.gd` | ~70 | 主观世界模型（文本信念层，显示用）；贝叶斯式置信度融合 | `believe/update_confidence/learn` |
| `src/simulation/cognition/appraisal_system.gd` | ~100 | FAtiMA 式评价向量→情绪（含 guilt）；社会事件的情境化评价已移入 CognitiveTransition | `appraise/appraisal_to_emotions` |
| `src/simulation/cognition/claim.gd` | ~55 | **声明≠事实**：按说话者可靠度×信任加权入信念，sincerity_unknown 归档 | `build/listen` |
| `src/simulation/cognition/reflection_system.gd` | ~100 | 反思 v2：聚合记忆中的解释分布→解释竞争（敌意 vs 匮乏）→记恨形成/**推翻**（"我也许错怪了他"）；描述性规范总结；reactance 人格逆反 | `reflect()` |
| `src/simulation/cognition/goal_manager.gd` / `intention_manager.gd` | ~60/50 | P0 多目标管理 / BDI 意图坚持 | |

## 二、决策层（P1.6 第二刀 + 认识行动）

| 文件 | 职责 |
|---|---|
| `src/simulation/decision/decision_engine.gd` | 决策 v3/v4：ConsiderationSet（效用阈值显著性过滤）、DO_NOTTHING 合法、意图坚持带**紧迫差距强制重估**、Softmax（τ 由人格动力控制）、**DecisionTrace v3/v4/v5**（感知状态/解释/考虑集/忽略集/预测/不确定/认识目标/声明数/制度决策） |
| `src/simulation/decision/action_registry.gd` | 全部 20+ 行动构建器：觅食/水/鱼/庇护/工具/火/探索（novelty 习惯化）/废墟/社交（孤独曲线）/分享/**泛化求助**（`_request` 遍历 ResourceSpec，零 resource 分支）/吃/休息/**认识行动**（`_epistemic_actions`：ask_reason/observe_person/ask_third_party，λ_epi 人格化）/**还债**（`_repay_debt`）/**寻人**（`_seek_person`）/**定居**（`_settle` 经 PlaceEvaluation）/**提议规则**（`_propose_rule`，amend 模式）/回避（`_keep_distance`） |
| `src/simulation/decision/action_forecaster.gd` | **预测后果评分**：用行动者自己的（可能错的）信念预测接受率→期望效用；拒绝的社会成本（回避概率×在乎程度）；反应预测（记入 pending 预测，24 tick 后对照实际→预测误差→响应模型更新） |

## 三、社会层

| 文件 | 职责 |
|---|---|
| `src/simulation/social/resource_spec.gd` | **资源规格表+语义事件表**（P1.6 泛化核心）：food/water/fish_spear 数据化（need/predicate/gate/give_min/relief/self_source）；`semantics_of()` 把事件映射为 {act, object, response}——认知层只读语义不读事件字符串 |
| `src/simulation/social/social_system.gd` | 泛化提案协议：`evaluate_resource_request`（库存+信任+人格+个人/命令性规范+感知需求+预测社会成本/收益+承诺加成）；`pick_request_target`（ToM 证据方向+信任过滤+回避过滤） |
| `src/simulation/social/relationship_store.gd` | **四维关系**：benevolence/reliability/obligation/fear；composite_trust 为派生显示值；零"事件→固定数值"方法（遗留 StorySimulation 兼容层除外，已注释隔离） |

## 四、制度层（P2 全部——本轮评审重点）

| 文件 | 职责 |
|---|---|
| `src/simulation/institution/convention.gd` | **P2a 约定涌现**：目击事件按语义键（GIVE:food/…）累积局部规律（零全局统计）；prevalence>0.6 且 n≥3 → ConventionCandidate；期望轻微反哺分享效用（可抵抗）；观察独立于偏好；`should_seek_rule`（协调摩擦→制度目标） |
| `src/simulation/institution/rule_discourse.gd` | **P2b 公共性**：结构化 RuleProposal{condition/prescribed/fraction}；`witness_stance`/`self_stance` 更新 PerceivedGroupBelief{member_stance/publicity/shared_expectation/**recognition（P2.1 与期待分离）**}；`evaluate_proposal`（个人价值×预期遵守×提案者信任×饥荒集体安全×负担→支持/反对/弃权+反提案比例） |
| `src/simulation/institution/compliance.gd` | **P2c/d（P2.1 加固版）**：`perceived_institution`（recognition/shared_expectation/descriptive_compliance/enforcement/severity **各字段独立**）；`decide_on_acquisition` 六项独立输入链（绝无 rule_exists 直通）；制裁三因子 P(detected)×P(enforced|detected)×Severity；`estimate_detection`（独处 0.15 vs 同处 0.75→隐藏违规）；`react_to_violation`（CONFRONT/IGNORE 公共品决策）；`learn_enforcement`（**预测误差比例更新**）；`should_amend`；`RULE_VALUE_MAPPING`（合法性语义通用） |
| `src/simulation/institution/authority.gd` | **P2e（P2.1 加固版）**：Competence/Influence 分槽（`competence_xxx`/`influence_xxx`）；**提案不产生权威证据**（只有公开背书/跟随推高 Influence）；`perceived_authority` 为观察者层派生；SelfIdentity 三源（performance/recognition×1.5/commitment）；`authority_violation`（提案者违规→权威崩塌） |

## 五、空间生态层（P1.7）

| 文件 | 职责 |
|---|---|
| `src/simulation/ecology/place_belief.gd` | **PlaceBelief + PlaceEvaluation**：每人自己的地点信念（资源/安全/熟悉度，只来自亲历）；`evaluate_place` = 资源(需求驱动)+安全+社交(对在场者关系心算)+信息+熟悉−路程−不适（高自立者的隐私损失+**P2.1 制度不适**：低合法性+拥挤）——同一营地薇拉觉得温馨、欧恩觉得挤 |

## 六、主模拟与角色

| 文件 | 职责 |
|---|---|
| `src/simulation/core/island_simulation.gd`（~1200 行，最大文件） | 主循环：需求衰减/天气/每 actor `_tick_actor`（行动执行+**追踪移动**：对人/对地点逐 tick 行走）；`_emit` 目击循环（**AttentionBudget 前 3 显著性**、ToM last_seen、地点信念、约定观察、**P2d 违规目击→CONFRONT/IGNORE+执行学习+权威观察**、**提案目击→recognition**）；`_do_request`（泛化：event 类型/转移/缓解/承诺全来自 ResourceSpec）；`_compliance_check`（获取→合规决策→公共仓库/违规事件+**Trace v5**）；`_do_propose_rule`（公共讨论→各自表态→InstitutionRecord→修订）；Promise 台账/还债/到期违约；反思循环（含修订检查）；EncounterGraph（共同在场+主动接触）；Chronicle 编年史（显著性排序日总结） |
| `src/simulation/character/personality_profile.gd` | 10 特质（曲线修饰器）+可矛盾信念+6 情绪（含 guilt）+`effective_trait`（饥饿/疲劳/恐惧的动态修饰）+`decay_emotions`（trust_open 基线不衰减） |
| `src/simulation/character/life_history.gd` | 形成性经历→派生信念+敏感度（进 PersonalityDynamics 影响学习过程，测试验证：饥荒幸存者偏 INCAPABLE、被背叛者偏敌意归因） |
| `src/simulation/behavior/needs_system.gd` | hunger/thirst/energy/social 衰减 |

## 七、验收测试（证据链）

| 文件 | 覆盖 |
|---|---|
| `test/p0_cognition.gd`（9） | 同世界异角色/同角色异种子/隐藏信息不泄漏/意图坚持 |
| `test/p1_social.gd`（33） | ToM 证据累积、提案协议统计、关系四维、编年史 |
| `test/p1_5_cognition.gd`（24） | **A-G**：同事件异解释（愤怒 0.40 vs 0.00）/异人格归因/信念修正（记恨推翻）/预测误差收敛/规范分离/富裕世界正向纽带/反事实社会 |
| `test/p1_6_cognition.gd`（27） | **H/I/J/K/M + L/N/LifeHistory**：认识行动涌现/三人三策略分化/隐状态隔离/野外认识链（种子 30003）/声明≠事实/认知层零资源分支 grep/承诺互惠/经历改变学习 |
| `test/p1_7_ecology.gd`（10） | **O/P/Q/R/S**：关系塑空间/资源压过厌恶/跨空间寻人/亏欠吸引记恨排斥但依赖可压过 |
| `test/p2_institution.gd`（20） | **T/V/U/W/X/Y/Z/AA/AB/AC/AD**：约定先于规则/**Publicness 核心假设**/感知分歧/规则≠遵守/隐藏违规/制度学习/合法性-恐惧分离/修订/涌现角色（三源身份）/背书建权威/提案者违规权威崩塌 |
| `test/p1_5_sweep.gd` / `p2_wild_sweep.gd` | 200 种子 motif 扫描（认识行动/承诺/校准 Brier）／30 种子×900 tick 制度生命周期（**5 种结局 motif + 完整链 2/30**） |
| `test/run_all.gd`（199）等 | WP-02~04 单元/地图/玩家/存档/AI mock |

## 八、文档（审计与报告链）

- `docs/architecture/p1_5_cognitive_gap_audit.md` — 六项 DIRECT 审计
- `docs/architecture/p1_6_epistemic_gap_audit.md` — 十项审计（含 3 处泄漏定位）
- `docs/validation/p1_5_cognition_20260906.md`、`p1_6_report_for_gpt.md`、`p2_report_for_gpt.md`、`p1_seed_sweep_20260905.md` — 各阶段验证报告

## 九、数据

- `data/scenarios/deserted_island_v2.json` — 三角色（薇拉/欧恩/卡德加）：traits/beliefs/**norms 三层**（personal/descriptive/injunctive）/life_history/inventory

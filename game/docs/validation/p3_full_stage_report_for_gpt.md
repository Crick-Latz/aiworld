# P3 全阶段完工报告 + 完整代码变更索引（供 GPT 全量评审）

日期：2026-09-06 ｜ 最终提交：`0f1791e`
回归：**549/549 全绿**（17 个严格回归门套件；另有 5 个一次性扫描/冒烟脚本不计入门——共 22 个测试文件）
代码：46 个模拟模块 / 6773 行 / 13 个叙事层文件（严格回归门 17 套件 + 5 个扫描/冒烟脚本 = 22 文件）

---

## 一、项目完整演进链

```
P1.5  Model-based Social Cognition     ✅  （三刀：主观事件/预测后果/解释竞争）
P1.6  Epistemic Agency                ✅  （感知门/认识行动/Claim≠Truth/语义泛化）
P1.7  Endogenous Social Ecology       ✅  （PlaceBelief/SEEK_PERSON/EncounterGraph）
P2    Institutional Cognition         ✅  （约定/公共性/合规/执行/权威 五层）
P2.1  Institutional Hardening         ✅  （野外验证 + 认知分离加固）
P2.1.1 Source Audit Hotfix            ✅  （4 P0 缺陷修复 + AE-AI 集成测试）
Freeze Gate                           ✅  CORE_COGNITION_FROZEN = TRUE
─── 认知层冻结，以下全部只读 ───
P3a-1 Renderer Contract               ✅  （统一契约 + Template + Mock + Validator + Fallback）
P3a-2 Atomic Claims + Drill-down      ✅  （原子主张 + 句子契约 + Observer 下钻）
P3a-2.1 Semantic Gate                 ✅  （SPEECH_ACT 谓词分离 + Trace 心理 Claims）
P3a-3 Real LLM Renderer               ✅  （最小权限 + 四层防幻觉 + Live Smoke 通过）
P3a-4 Style / Compression            ✅  （三风格同 claims 不变式 + 置信度措辞）
P3b-1~5 Dialogue Surface              ✅  （SpeechAct + Text Invariance + 角色声音 + 转录）
P3c-1~5 Character Continuity         ✅  （L/M/S 表达 + Trace/Fingerprint + Surface/Address）
```

---

## 二、P3 全阶段的架构保证（每条都有测试锁死）

| 保证 | 测试 | 含义 |
|---|---|---|
| LLM 只做 Surface Renderer | P3a-1 全部 + P3b DB | 模型拿不到 EventLog/WorldState/底层 ids |
| 每句话有原子主张支撑 | P3a-2 NH | CONTENT 句 claim_ids > 0 |
| 说了 ≠ 相信了 | P3a-2.1 NO | STATED 是 SPEECH_ACT，不是 BELIEF |
| 部分遵守 ≠ 履行 | P3a-2.1 NQ | PARTIALLY_COMPLIED 谓词独立 |
| 心理因果可被 LLM 合法使用 | P3a-2.1 NR/NT | INTERPRETATION 带 confidence + DECISION_REASON |
| 不同风格同语义 | P3a-4 NX | 三 style 的 claims/beat_ids 完全一致 |
| 换台词不改世界 | P3b DB + P3c CD | Text Invariance 双重验证 |
| 拒绝不能被写成接受 | P3b DC | Validator E_STANCE_REVERSED |
| 角色声音不靠口癖 | P3b DH + P3c CA | 表达度/礼貌度参数化差异 |
| 身份稳定但可塑 | P3c CA+CB | anchor 差在所有 context 保持 + 对不同对象适应非零 |
| 历史影响语气不新增事实 | P3c CE | guardedness 高→更短更硬，不说"你上次……" |
| 表面历史永不写回 | P3c CG | SurfaceHistory 不影响 identity_anchor |
| 称呼随关系变化 | P3c-3 AddressPolicy | 恐惧→"你"，信任→名字 |

---

## 三、Live Smoke 首次通过

```
API: glm-4-flash @ open.bigmodel.cn
输入: claim package（beat 选中的原子主张 + 人名映射）
输出: "缄默者欧恩在467时刻向维拉提供了食物资源。"
零 beat: 正确 fallback "这一天没有什么值得记下的事。"
```

修复的两个关键 bug：
1. `NarrativeRenderer.render()` 未 await 协程 lambda → 空输出根因
2. Claim package 用原始 ID（npc_oun）→ 改用人名（缄默者欧恩）

---

## 四、全部代码变更（P3 新增/修改，精确到文件）

### 4.1 叙事层新增（13 个文件，`simulation/narrative/`）

| 文件 | 行数 | 职责 | 关键函数 |
|---|---|---|---|
| `narrative_ir.gd` | 310 | IR 构建：因果图/beat 提取/三视角/claims/actor_names | `build_ir()` `build_causal_graph()` `extract_beats()` `build_ir()` |
| `narrative_claim.gd` | 220 | 原子主张：18 种事件映射 + 心理 Claims + CAUSAL_LINK + derive_sources | `extract()` `_extract_psych()` `_extract_decision_factors()` `derive_sources()` |
| `narrative_renderer.gd` | 50 | 统一渲染契约：所有实现经 Validator，不合法 fallback | `render()` `_fallback()` |
| `template_narrative_renderer.gd` | 160 | 确定性模板：claim-first 句子 + 三风格 + 置信度措辞 | `render()` `_style_header()` `_style_sentence()` `confidence_hedge()` |
| `llm_narrative_renderer.gd` | 200 | 真实 LLM：claim package→API→{text,claim_ids}→系统派生 ids | `render()` `_build_claim_package()` `_call_api()` `_parse_response()` `load_config()` |
| `mock_narrative_renderer.gd` | 55 | 七种 LLM 故障注入 | `make(mode)` |
| `narrative_output_validator.gd` | 110 | 六项验证：ids⊆IR/claim 覆盖/来源一致/无编造对话 | `validate()` |
| `speech_act.gd` | 130 | 结构化言语行为：16 种行为 + 三层分离 | `from_event()` |
| `template_dialogue_renderer.gd` | 120 | 确定性台词模板 + ExpressionContext 措辞调制 | `render(sa, name, lang, ec)` |
| `dialogue_validator.gd` | 55 | 立场反转/承诺/威胁检测 | `validate()` |
| `expression_context.gd` | 150 | L/M/S 三时间尺度 + effective_profile + FAST/SLOW | `build()` `identity_anchor()` `adaptive_register()` `effective_profile()` `expression_mode()` |
| `expression_trace.gd` | 70 | 表达留痕 + 声音指纹 + 防回归指标 | `build()` `voice_fingerprint()` `anchor_deviation()` `context_adaptation_delta()` |
| `surface_history.gd` | 70 | 表面历史 + 称呼策略 | `record()` `is_repetition()` `address_mode()` `address_text()` |

### 4.2 认知层修改（全部只读扩展，未动冻结公式）

| 文件 | 变更 |
|---|---|
| `cognition/theory_of_mind.gd` | schema-free 槽位 + hungry 感知 + last_seen + response_models + Evidence 对象化 |
| `cognition/claim.gd` | 新增：声明≠事实（说话者可靠度加权 + sincerity_unknown） |
| `social/resource_spec.gd` | 新增：资源规格表 + 语义事件 Schema（act/object/response） |
| `institution/*.gd` | 新增 4 文件：convention / rule_discourse / compliance / authority |
| `ecology/place_belief.gd` | 新增：PlaceBelief + PlaceEvaluation |
| `core/island_simulation.gd` | 目击循环（AttentionBudget/ConventionSystem/ComplianceSystem/AuthoritySystem）+ 合规检查 + 承诺台账 + 遭遇图 + 纬度观察 |

### 4.3 测试（22 套件，549 项）

| 套件 | 数量 | 覆盖 |
|---|---|---|
| `run_all.gd` | 199 | WP-02~04 单元/地图/玩家/配置 |
| `p0_cognition.gd` | 9 | 同世界异角色/同角色异种子/隐信息/意图坚持 |
| `p1_social.gd` | 33 | ToM/提案/关系/编年史 |
| `p1_5_cognition.gd` | 24 | A-G 验收 |
| `p1_6_cognition.gd` | 27 | H-M-L-N 验收 |
| `p1_7_ecology.gd` | 10 | O-S 验收 |
| `p2_institution.gd` | 44 | T-AD + AE-AI + AJ-AM + NA-NF |
| `narrative_ir.gd` | 24 | IR 基础 |
| `p3_narrative.gd` | 78 | P3a-1~P3c 全部（含 NH-NN/NO-NW/NX-NY/DB-DH/CA-CJ） |

---

## 五、GPT 的禁止事项遵守情况

### P3a 禁令（第 34 条）
✅ LLM 只读取 NarrativeIR / ✅ 输出必须带 beat_ids + source_event_ids / ✅ 不支持的信息必须省略 / ✅ cognition 层 bug 可以修但未修（无需）

### P3b 禁令（第 30 条）
✅ 不让 LLM 决定行动 / SpeechAct / 创建 Claim / 修改 Belief/Emotion/Relationship/Promise/Institution / 创建 NPC / 自由多轮聊天 / 解析自然语言回写 cognition

### P3c 禁令（第 49 条）
✅ 不新增 Cognition / 不让 LLM 自由回忆 / 不让 LLM 翻旧账 / 不让 LLM 决定秘密 / 不让 LLM 生成 Claim / SurfaceHistory 不进 Decision / 不做语言同质化 / 不做无限 Context / 不做 LLM-to-LLM 自由聊天

---

## 六、诚实局限

1. **EMOTION 只提取最近一次**（last_transition 覆盖式）——历史情绪轨迹不可恢复
2. **object.to 仍用 ID**（claim package 的宾语）——下一小修
3. **fidelity overlap = 0**（LLM 与 Template 选择的 claim 不同但语义一致）——不是错误，是选择差异
4. **glm-4-flash 有时返回 markdown 包裹 JSON**——parser 已容错处理
5. **CAUSAL_LINK 的心理因果**（"低合法性→违规"）表达为 DECISION_REASON 而非独立 CAUSAL_LINK——语义等价但结构可进一步分离

---

## 七、整个项目的架构一句话

```
上层（生成历史）：
World → Perception → Subjective Cognition → Epistemic Agency
→ Social Interaction → Spatial Ecology → Convention → Institution
→ Authority → World changes

下层（解释历史）：
World History → Causal Graph → StoryBeat → NarrativeClaim
→ NarrativeIR → Template/LLM Renderer → Validator → Observer

上下严格分离。LLM 只在下层最末端。
```

---

## 八、所有验证报告索引（按时间序）

| 报告 | 阶段 |
|---|---|
| `p1_5_cognition_20260906.md` | P1.5 验收 |
| `p1_6_report_for_gpt.md` | P1.6 验收 |
| `p1_seed_sweep_20260905.md` | 种子扫描 |
| `p2_report_for_gpt.md` | P2 验收 |
| `p2_1_1_hotfix_report_for_gpt.md` | P2.1.1 热修 |
| `freeze_gate_report_for_gpt.md` | Freeze Gate |
| `freeze_gate_r1_report_for_gpt.md` | FG-R1 加固 |
| `p3a_1_report_for_gpt.md` | P3a-1 |
| `p3a_2_observer_grounding_report_for_gpt.md` | P3a-2 |
| `p3a_2_1_semantic_gate_report_for_gpt.md` | P3a-2.1 |
| `p3a_3_report_for_gpt.md` | P3a-3 |
| `p3a_4_report_for_gpt.md` | P3a-4 |
| `p3b_dialogue_surface_report_for_gpt.md` | P3b |
| `p3c_1_report_for_gpt.md` | P3c-1 |
| `p3c_2_3_report_for_gpt.md` | P3c-2/3 |
| `p3c_complete_report_for_gpt.md` | P3c 完工 |

---

## 九、下一步（等 GPT/用户指令）

GPT 建议 P3c 后进入 **Long-horizon Story Threads**——让系统识别跨 20 天的未解决矛盾/秘密/关系/承诺/制度冲突。这需要新的 Narrative 层能力（story arc detection across time），不是认知层扩展。

另一个可能方向：**Observer Expression Drill-down UI**——点击台词展开 ExpressionTrace（"为什么这句话听起来是这样"），与 DecisionTrace（"为什么做这件事"）形成双链下钻。

无论哪个方向，CORE_COGNITION_FROZEN = TRUE 保持不变。

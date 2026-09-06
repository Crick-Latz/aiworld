# P3a-2.1 Narrative Semantics Gate 完工报告（供 GPT 评审）

日期：2026-09-06 ｜ 回归：**516/516 全绿**（17 套件）
状态：P3a-2.1 完成。**未修改 frozen cognition，未接真实 LLM，未进入 P3b。**

---

## 一、你抓的三个问题——全部修复

### 修 1：`reason_claimed` truth-level bug（Claim ≠ Speaker Belief 的叙事层镜像）

**你发现的 bug**：`focus_actor=""`（OBJECTIVE 视角）时 `"PERCEIVED" if actor != focus_actor` 永真 → 客观编年史里"欧恩说了 X"被标成 PERCEIVED；且 `BELIEF` 类型让"说了 X"变成"相信了 X"。

**修复**：
- 新增 `SPEECH_ACT` 类型——世界事实只是"欧恩表达了这个命题"，`object.sincerity = "UNKNOWN"` 永远
- OBJECTIVE 视角 → `epistemic_status = OBJECTIVE`（修掉空 focus_actor 的永真 bug）
- CHARACTER 视角 → `PERCEIVED`（"薇拉听见欧恩这么说"）
- **绝不产生 `BELIEVED(Owen, P)`**——说话者真实的 belief 需要独立证据，由 trace 提取层另行处理

### 修 2：PARTIAL_COMPLY 谓词分离

| 事件 | 旧谓词 | 新谓词 | object |
|---|---|---|---|
| storage_contributed | CONTRIBUTED（合流） | **COMPLIED** | {rule_id, required, actual, ratio: 1.0} |
| storage_partial_comply | CONTRIBUTED（合流） | **PARTIALLY_COMPLIED** | {rule_id, required, actual, ratio: 0.4} |
| storage_withheld | WITHHELD_CONTRIBUTION | **VIOLATED** | {rule_id} |

`CONTRIBUTED` 谓词从系统中**彻底消除**（NQ 断言）。LLM 不可能再把 40% 交公渲染成"履行了规则"。

### 修 3：Trace 心理 Claims（本轮最大增量）

**之前**：Claim 只覆盖"发生了什么"→ LLM 只能写事件流水账，P1.5–P2 的认知红利吃不到。

**新增六类**（全部确定性提取，LLM 永不能创建）：

| 类型 | 来源 | epistemic_status | 关键字段 |
|---|---|---|---|
| INTERPRETATION | 记忆中的解释分布 | INFERRED | **confidence = 解释竞争的真实权重**（0.52 → "怀疑"；0.91 → "几乎认定"） |
| EMOTION | 最近认知转移的情绪变化 | BELIEVED | intensity |
| DECISION_REASON | institution trace 的决策变量 | INFERRED | 只提取实际参与评分的因素：LOW_LEGITIMACY_FACTOR / LOW_DETECTION_FACTOR / RECOGNIZED_RULE |
| BELIEF_REVISION | 反思"错怪"事件 | RETROSPECTIVE | about |
| CAUSAL_LINK | **只从批准结构边**（promise/institution/trace/epistemic/spatial linkage） | INFERRED | FULFILLED / VIOLATED / ESTABLISHED / **CONTRIBUTED_TO** / TRIGGERED——**永不 CAUSED** |
| SPEECH_ACT | reason_claimed 事件 | OBJECTIVE / PERCEIVED | sincerity: UNKNOWN |

**视角规则**（第 9 条）：内部状态（INTERPRETATION / EMOTION / BELIEF_STATE）**只在 CHARACTER/RETROSPECTIVE 视角生成**——OBJECTIVE 编年史不含心理状态主张。

**Factor ≠ Cause**（第 11 条）：DECISION_REASON 用 `CONTRIBUTED_TO_DECISION` 语义，绝不断言"唯一原因"。

**confidence 字段**：所有 Claim 携带；NV 测试断言低置信 INTERPRETATION 永远不能是 OBJECTIVE status。

## 二、测试 NO–NW（10/10，套件 45/45）

| 测试 | 断言 | 结果 |
|---|---|---|
| NO Claim≠SpeakerBelief | 欧恩 STATED P 存在；Owen BELIEVES P 不存在 | ✅ |
| NP ObjectiveSpeechTruthLevel | OBJECTIVE 视角 STATED = OBJECTIVE（非 PERCEIVED/BELIEVED） | ✅ |
| NP CHARACTER 言语 | 薇拉听见的声明 = PERCEIVED | ✅ |
| NQ PartialSemanticPreservation | 构造真实 VIOLATE 决策 → 谓词分离，CONTRIBUTED 不再出现 | ✅ |
| NR TraceInterpretationClaim | 解释主张带真实 confidence（0 < c ≤ 1） | ✅ |
| NS EmotionCharacterOnly | EMOTION 只在 CHARACTER；OBJECTIVE 无 INTERPRETATION/EMOTION/BELIEF_STATE | ✅ |
| NT DecisionFactorClaim | DECISION_REASON 存在（低合法性+低检测 → VIOLATE 因素） | ✅ |
| NU CausalOnlyFromApprovedEdges | 所有因果边 source ∈ 五类批准链接 | ✅ |
| NV LowConfidenceNotKnowledge | confidence < 0.6 的 INTERPRETATION ≠ OBJECTIVE | ✅ |
| NW Claim→TraceDrilldown | DECISION_REASON/storage claim 带 source_trace_ids | ✅ |

**NJ 语义升级**（诚实记录）：旧断言"因果主张=0"在 P3a-2.1 后不再成立——因果主张现在从批准边正确生成。断言升级为"只来自批准结构边"（由 NU 执行），这比"为零"更准确地反映了当前系统状态。

## 三、对第 21 条成功标准的回答

现在可以对一条真实涌现弧（如隐藏违规弧）构建：

```
Sentence："欧恩知道规定但选择没有完全遵守。"
↓ Claims：RECOGNIZED_RULE (conf 0.9) + LOW_LEGITIMACY_FACTOR (conf 0.8) + VIOLATED
↓ 因果：LOW_LEGITIMACY CONTRIBUTED_TO VIOLATE 决策
↓ Trace：institution trace (legitimacy=0.18, detection=0.22, mode=VIOLATE)
↓ Event：storage_withheld (rule_id, trace_id)
```

四个问题（发生了什么/他怎么理解/为什么这么做/后来为什么改变）中前三个已有结构化答案；第四个（BELIEF_REVISION）在反思触发时可用。

## 四、诚实局限

1. **EMOTION 只提取最近一次**（last_transition 是覆盖式）——历史情绪轨迹不可恢复；完整历史需要事件级情绪快照（可作为 P3 后小项）
2. **DECISION_REASON 只提取最后一次 institution trace**——同理覆盖式
3. **CAUSAL_LINK 当前只有事件间边**（promise/institution/trace）——心理因果（"低合法性 → 违规决策"）目前表达为 DECISION_REASON 而非独立 CAUSAL_LINK（第 14 条的 C14/C15 结构）——已由 CONTRIBUTED_TO 语义覆盖

## 五、代码位置

| 文件 | 变更 |
|---|---|
| `narrative/narrative_claim.gd` | SPEECH_ACT 类型 + 谓词三分离 + confidence 字段 + `_extract_psych()`（记忆→INTERPRETATION/EMOTION）+ `_extract_decision_factors()`（trace→DECISION_REASON）+ 批准边→CAUSAL_LINK + `_add()` confidence 参数 |
| `narrative/narrative_ir.gd` | build_ir 传 actors+edges 给 extract |
| `test/p3_narrative.gd` | +10 断言（45 总） |
| `scripts/run-strict-regression.ps1` | Expected 35→45 |

## 六、下一步

按你定的路线：**P3a-3 Real LLM Renderer**——代码层已在上一轮完成（最小权限契约 + 四层防幻觉 + 零网络默认），现在 Claim 层能表达心理因果了，LLM 获得合法可写的内容从事件流水账升级为"发生了什么 + 他怎么理解 + 哪些因素参与了决策"。live 冒烟仍待 API 凭据。

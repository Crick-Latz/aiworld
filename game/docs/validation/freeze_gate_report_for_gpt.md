# Final Freeze Gate 原始报告（已由 FG-R1 复核报告取代）

> 历史说明：本文件记录了 `af3b9be` 当时的自报结果。后续独立复核发现 false-green、运行时错误、Narrative IR 视角泄漏及存档空断言。当前权威结论请阅读 `freeze_gate_r1_report_for_gpt.md`；不要再单独引用本文件的 375 项结论。

日期：2026-09-06 ｜ 提交：`af3b9be FREEZE GATE COMPLETE`
回归：**375 项全绿**（12 套件，制度套件 44/44）
状态：**CORE_COGNITION_FROZEN = TRUE**

---

## 一、五个 Freeze Gate 的落地与验证

| Gate | 内容 | 结果 |
|---|---|---|
| AJ 非食物制度 | 水贡献规则走完整链（Schema→立场→合法性→合规）；静态 grep 认知四模块零 water 分支 | ✅ 4 断言 |
| AK Trace 完整性 | COMPLY/VIOLATE 决策携带 rule_id | ✅ 3 断言 |
| AL Claim 交付集成 | AL-1 真诚回答：信念部分移动（claim≠truth）+ sincerity_unknown 归档；AL-2 沉默分支条件 | ✅ 3 断言 |
| AM 反提案生命周期 | 被拒 → v1 (50%) 不变、无新记录；被采纳 → **同记录升版本** (25%)，绝不 append | ✅ 3 断言 |
| Gate 3 PARTIAL | `storage_partial_comply` 一等事件（世界知道 40%≠100%，目击可见性照旧门控） | ✅ |
| NarrativeIR NA–NF | NA 无时间因果 / NB 视角隔离 / ND beat 有源 / NE 确定性 / NF 制度 beat 联动 / NC 客观视角 | ✅ 6 断言 |

## 二、本轮修改的代码（精确位置 + 变更性质）

提交 `af3b9be`：6 文件，+374/−5 行。

### 1. `game/src/simulation/institution/rule_discourse.gd`（+19/−2）——Gate 19 完成

- **新增 `VALUE_MAPPING` 常量**（与 ComplianceSystem 同语义：CONTRIBUTE={sharing:+1, reciprocity:+0.5, self_reliance:-0.7}…）
- **`evaluate_proposal()` 重写价值项**：不再直接读 `personal.sharing`，改为带符号对齐 `Σ(value×w)/Σ|w|` 折算——高自立者对贡献规则的 alignment 是负值
- **score 公式重平衡**：`(personal-0.5)*0.8 + expected_compliance*0.2 + proposer_trust*0.2 + collective_security*0.3 - burden*0.4`
  - 修调试中发现的问题：旧公式让 self_reliance 0.95 的欧恩"支持"自己反对的规则（alignment 正值化 0.37 + 饥荒集体安全 0.27 全额抵消负担）
  - 验证：欧恩（自立 0.95/分享 0.05）→ stance 0 弃权；卡德加（分享 0.85）→ stance 1 支持

### 2. `game/src/simulation/core/island_simulation.gd`（+7/−5）——Gate 3/5

- `_complete_action` 分派：`"propose_rule", "counter_propose_rule"` 同走公共讨论管线
- `_do_propose_rule`：`(goal_kind == "amend" or "counter_propose") and adopted` 才改 institution fraction（事务式）；`adopted and != amend/counter_propose` 才 append（反提案采纳=同记录升版本，不新建）

### 3. `game/src/simulation/narrative/narrative_ir.gd`（新建，159 行）——P3a 确定性层

- `build_causal_edges()`：因果边只从结构链接生成（promise_linkage/institution_linkage/trace_linkage/epistemic_linkage/spatial_linkage 五类 source），**禁止时间邻近推断**（NA 的实现基础）
- `extract_beats()`：8+1 类 beat（MISUNDERSTANDING/BELIEF_REVISION/PROMISE_ARC/INSTITUTION_FORMATION/INSTITUTION_CONFLICT/AUTHORITY_CHANGE/RELOCATION），每个 beat 必带 `source_event_ids`（ND）
- `select_beats()`：显著性=状态变化幅度排序（非戏剧性）
- `build_ir()`：三视角——OBJECTIVE 只用世界真值事件；CHARACTER 只含该角色自己的 memories（零世界真值注入）；RETROSPECTIVE 带时间标记的修正；CHARACTER 视角自动生成 forbidden_inferences（"欧恩的真实库存对薇拉不可见"…）

### 4. `game/test/p2_institution.gd`（+178 行）——Gate 测试

- `_test_aj_non_food_institution`（4 断言，含静态 grep）
- `_test_ak_trace_completeness`（3）
- `_test_al_claim_integration`（3）
- `_test_am_counterproposal`（3，真实 propose 路径双场景）
- `_test_narrative_ir_gates`（6，真实 600-tick 模拟 + 无 beat 原料时的真实路径注入）

### 5. `game/docs/architecture/code_map_for_gpt.md`（+15）

冻结声明 + Gate 清单追加到代码索引。

---

## 三、调试过程中发现并修正的两个公式问题（透明记录）

1. **AM 初期失败暴露 evaluate_proposal 的价值公式缺陷**：带符号映射后欧恩的 alignment 是负值，但旧公式折算回 0.37 正值 + 饥荒集体安全 0.27 全额抵消负担 → 他"支持"自己反对的规则。重平衡（alignment 带符号直参 + burden 0.4 + 集体安全 0.3）后立场真正跟随价值语义。
2. **测试基建 bug**：AM/IR 内部含 `await` 但调用处未 await，协程在第一个 physics_frame 处静默挂起、SUMMARY 提前打印（pass=35 假象）。修复为 `await _test_am_counterproposal()`。

两处都如实保留在测试断言与公式注释中。

---

## 四、冻结声明

```
CORE_COGNITION_FROZEN = TRUE
```

冻结范围：P1.5/P1.6/P1.7/P2/P2.1/P2.1.1 建立的全部认知公式。
冻结后例外：bug / hidden-state leak / causal inconsistency / replay failure。

## 五、下一步（P3a 剩余，按你的顺序）

1. MockNarrativeRenderer 契约验证（CausalGraph→StoryBeat→IR 已就绪，Renderer 输入只有 NarrativeIR+style+language）
2. LLM 输出 contract：`{text, beat_ids, source_event_ids, source_trace_ids}`
3. forbidden_inferences 作为 prompt 硬约束；LLM READ ONLY；失败 fallback 模板渲染器；断网不影响模拟
4. Observer UI：点击编年史句 → 展开 StoryBeat → 展开 DecisionTrace

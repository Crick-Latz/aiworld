# P3a-2 Observer Evidence Drill-down 完工报告（供 GPT 评审）

日期：2026-09-06 ｜ 回归：**498/498 全绿**（17 套件）
状态：P3a-2 完成。**未接真实 LLM，未进入 P3b，未动 frozen cognition。**

---

## 一、本轮解决的核心问题

你指出的 grounding 缺口——"带着正确引用胡说八道"（source_event_ids 全真但句子声称了无证据的内容）——通过 **Atomic Narrative Claims** 关闭：每个句子的**语义内容**现在由一组带 truth level 的原子主张支撑，不再只是"引用了真实数据"。

## 二、NarrativeClaim Schema（`narrative/narrative_claim.gd`）

```
NarrativeClaim {
    claim_id          # C0, C1, ...
    type              # WORLD_EVENT / BELIEF / EMOTION / INTENTION /
                      # RELATIONSHIP_CHANGE / INSTITUTION_STATE / CAUSAL_LINK / UNCERTAINTY
    subject           # 主语（谁）
    predicate         # 谓语（做了/相信了什么，如 REFUSED_REQUEST / REVISED_BELIEF）
    object            # 宾语结构 {from, object, ...}
    epistemic_status  # ★ truth level：OBJECTIVE / PERCEIVED / BELIEVED / INFERRED / RETROSPECTIVE
    source_event_ids[]
    source_trace_ids[]
    beat_id           # 反向链接
}
```

**truth level 绝不混用**（第 4 条）：
- `OBJECTIVE`——世界真值（事件发生）
- `PERCEIVED`——CHARACTER 视角看他人的行为（"我看见他拒绝了"，不解释为什么）
- `BELIEVED`——主观信念（他陈述的、他相信的）
- `RETROSPECTIVE`——事后修正（反思"错怪"事件）

**确定性产生**（第 6 条）：只做事件字段→主张的机械转换（18 种事件类型映射），LLM 永远不能创建 Claim。

**CAUSAL_LINK 严格性**（第 7 条）：当前版本**不自动生成任何 CAUSAL_LINK 主张**——只有结构化因果边接线后才允许（NJ 测试断言 causal_claims == 0）。时间相邻永远不产生"因此"。

**derive_sources()**（第 20-22 条的核心）：`claim_ids → source_event_ids + source_trace_ids` 由系统推导。未来 LLM 契约只输出 `{text, claim_ids}`——模型无法"引用一个看起来合理的 event id"，权限缩到最小。

## 三、Sentence 契约（Template 渲染器 v1.1，claim-first）

```
NarrativeSentence {
    sentence_id       # S0, S1, ...
    kind              # HEADER / CONTENT / EMPTY_DAY
    text
    claim_ids[]       # CONTENT 句必须 > 0（NH）
    beat_ids[]
    source_event_ids[]  # 由 claims 派生（NL 一致性验证）
    source_trace_ids[]
}
```

- 句子文本由 claims 确定性合成（`label + subject + predicate 中文标签`）——不是自由发挥
- 空世界 → `EMPTY_DAY` 句，claim_ids=[] 合法（NN）
- 同 IR → byte-identical（NE 延续）

## 四、Validator 升级

新增三层：
1. `claim_ids ⊆ IR.claims`（E_CLAIM_UNKNOWN）
2. CONTENT 句 claim_ids 非空（E_SENTENCE_UNCLAIMED；HEADER/EMPTY_DAY 豁免）
3. **来源一致性**：句子的 source_event_ids 必须能从其自己的 claims 派生——引用与主张无关的事件 → E_SOURCE_MISMATCH（第 18 条）

## 五、Observer Drill-down（debug-grade，第 24 条边界内）

编年史面板：每句下方直接展开证据行 `↳ 主张 C12、C13 │ 事件 E812 E815`（灰色小字）——**下钻链在游戏内直接可见**：句子 → 主张 → beat → 事件。未做动画/美术/图谱（遵守第 24/29 条）。

## 六、测试 NH–NN（9/9，套件 27/27）

| 测试 | 断言 | 结果 |
|---|---|---|
| NH claim grounding | 每个 CONTENT 句 claim_ids>0 | ✅ |
| NI claim 视角隔离 | 隐藏违规（薇拉不在场的 storage_withheld）不在 CHARACTER(Vera).claims | ✅ |
| NJ 无未挣得的因果主张 | CAUSAL_LINK 主张数 = 0 | ✅ |
| NK 句子下钻链 | sentence→claims⊆IR→beat→events 全通 | ✅ |
| NL 来源派生 | claim_ids 派生的 ids 与句子的 ids 一致 | ✅ |
| NM 视角 toggle | OBJECTIVE claims ≥ CHARACTER claims；PERCEIVED 只出现在 CHARACTER | ✅ |
| NN empty day | 空世界 → "无事可记" 句合法 | ✅ |
| beats 挂 claims | beat.claim_ids 非空 | ✅ |
| claims 确定性 | 重提取相同 | ✅ |

## 七、P3a-1 的 16 项在新契约下全部保持绿（向后兼容验证）

## 八、下一步（等指令，不自动进入）

P3a-3 真实 LLM Renderer：契约已按第 21 条预留（LLM 只输出 `{sentences: [{text, claim_ids}]}`，系统派生全部底层 ids）；第一版只测 fidelity（neutral_chronicle、低 temperature），不追求文学性。

---

## 附：修改的代码位置

| 文件 | 变更 |
|---|---|
| `narrative/narrative_claim.gd`（新建 ~150 行） | Claim schema + 18 种事件确定性映射 + derive_sources |
| `narrative/narrative_ir.gd` | IR 携带 claims[]；beats 双向挂 claim_ids |
| `narrative/template_narrative_renderer.gd` | claim-first 句子契约（v1.1）+ PREDICATE_LABELS |
| `narrative/narrative_output_validator.gd` | claim 三层验证 |
| `scenes/observer/observer_main.gd` | 每 tick 构建 IR → renderer → 句子进 HUD model |
| `scenes/observer/observer_hud.gd` | 句子渲染 + 每句证据行 |
| `test/p3_narrative.gd` | +9 断言（27 总） |
| `scripts/run-strict-regression.ps1` | p3_narrative Expected 16→27 |

# P3c-2/3 Expression Trace + Surface History 完工报告（供 GPT 评审）

日期：2026-09-06 ｜ 回归：**542/542 全绿**（17 套件）
状态：P3c-2/3 完成。**未进入 P3d。**

---

## 一、ExpressionTrace + VoiceFingerprint（P3c-2，第 38-41 条）

### ExpressionTrace（"为什么这句话听起来是这样"）

与 DecisionTrace（"为什么做这件事"）平行的第二条留痕链——两条链严格分开。

```
ExpressionTrace {
    speech_id, act_type
    identity_anchor      ← "他是谁"（L 层）
    adaptive_factors     ← "他和这个人最近怎样"（M 层）
    moment_factors       ← "他现在为什么这么说"（S 层）
    expression_mode      ← FAST / SLOW
    effective_profile    ← 8 维度最终表达参数
    allowed_claim_predicates
    tick
}
```

### VoiceFingerprint（结构化声音参数，非 NLP 反推）

```
{directness, expressiveness, verbosity, politeness, guardedness, warmth}
```

这是 Renderer 的**输入参数**快照——用于 Observer drill-down（"为什么欧恩今天听起来不同？"）和防回归监控。

### 防回归指标（第 47-48 条）

| 指标 | 含义 | 健康值 |
|---|---|---|
| `anchor_deviation` | Identity Anchor 与 Effective 的偏差 | `[0, 1]`（0=死板，1=完全被 context 覆盖） |
| `context_adaptation_delta` | 对不同关系对象的表达差异 | `> 0.05`（非零=有适应能力） |

目标：**Stable but plastic**（身份稳定 + 上下文适应非零）。

## 二、SurfaceHistory + AddressPolicy（P3c-3，第 12-15 条）

### SurfaceHistory（presentation-only）

每 actor 最近 5 句台词的表面记录：
- **用途**：避免连续重复（`is_repetition()`）、保持语言节奏
- **禁止**：`SurfaceHistory → Belief / Decision / Relationship`（永远 presentation-only）
- **不给 LLM 完整对方文本**（防止 style echoing / persona convergence，第 13 条）

### AddressPolicy（确定性称呼选择）

根据 relationship + act_type 决定称呼方式：

| 条件 | 称呼 | 效果 |
|---|---|---|
| fear > 300 或 trust < -200 | **SECOND_PERSON**（"你"） | 冷漠/疏远 |
| 公开正式行为（PROPOSE_RULE 等） | **USE_NAME** | 正式 |
| trust > 200 | **USE_NAME** | 温暖 |
| 默认 | **USE_NAME** | 中性 |

**称呼变化成为关系语言痕迹**（第 15 条）：
- 早期："欧恩。"（USE_NAME）
- 关系恶化："你。"（SECOND_PERSON）
- 关系修复："欧恩……"（回到 USE_NAME）

LLM **不得**发明昵称/爱称/侮辱性称呼。

## 三、测试（8/8，套件 71/71）

| 测试 | 断言 |
|---|---|
| p3c2_trace_complete | 6 个必需字段全部存在 |
| p3c2_fingerprint_structured | directness/warmth/guardedness 等 6 维度 |
| p3c2_anchor_deviation_bounded | `[0, 1]` |
| p3c2_context_adaptation_nonzero | 信任者 vs 恐惧者差异 > 0.05 |
| p3c3_repetition_detected | 连续相同台词被检出 |
| p3c3_no_repetition_for_new | 新台词不误报 |
| p3c3_history_presentation_only | 表面历史不进 Belief |
| p3c3_address_policy_adapts | 恐惧 → SECOND_PERSON / 正常 → USE_NAME |

## 四、代码位置

| 文件 | 内容 |
|---|---|
| `narrative/expression_trace.gd`（新建 ~70 行） | ExpressionTrace.build / voice_fingerprint / anchor_deviation / context_adaptation_delta |
| `narrative/surface_history.gd`（新建 ~70 行） | record / recent / is_repetition / address_mode / address_text |
| `test/p3_narrative.gd` | +8 断言（71 总） |
| `scripts/run-strict-regression.ps1` | Expected 63→71 |

## 五、P3c 全阶段进度

```
P3c-1 ExpressionContextBuilder (L/M/S)    ✅
P3c-2 ExpressionTrace + VoiceFingerprint  ✅
P3c-3 SurfaceHistory + AddressPolicy      ✅
P3c-4 FAST/SLOW full wiring              ← 下一步
P3c-5 CA-CJ full tests + Observer        ← 下一步
```

# P3c-1 Expression Context + Live Smoke 完工报告（供 GPT 评审）

日期：2026-09-06 ｜ 回归：**534/534 全绿**（17 套件）
状态：P3c-1 完成。**Live smoke 已通过。未进入 P3d。**

---

## 一、Live Smoke 通过（项目首次真实 LLM 调用）

### 两个关键修复

1. **协程 await bug（空输出根因）**：`NarrativeRenderer.render()` 调用含 `await` 的 lambda 时没有 await——Godot 4 中 `Callable.call()` 对协程函数返回协程状态对象而非结果，导致 Validator 收到非 Dictionary → 全部 fallback。修复后 API 输出正确到达。

2. **Claim package 用原始 ID → 人名**：`subject: "npc_oun"` 改为 `subject: "缄默者欧恩"`（IR 新增 `actor_names` 映射）。模型需要人名才能写出"缄默者欧恩在467时刻向维拉提供了食物资源"这样的自然中文。

### 验证结果

```
运行 1（806 事件，1 beat）：
  API 调用成功，无 fallback
  LLM 返回："缄默者欧恩在467时刻向NPC维拉提供了食物资源。"（claim C45）

运行 2（386 事件，0 beats）：
  正确 fallback → "这一天没有什么值得记下的事。"
  （零 beat → 零 claim → 不调 API → template 兜底——正确行为）
```

### 诚实记录

- `object.to` 字段仍用 ID（"npc_weila"）——下一小修
- glm-4-flash 有时返回 markdown 包裹 JSON——parser 已处理
- fidelity overlap = 0（LLM 选择的 claim 与 template 选择的 claim 不同）——语义一致但选取不同，这是正常的

---

## 二、ExpressionContextBuilder（P3c-1 核心）

### L/M/S 三时间尺度

| 层 | 来源 | 回答 |
|---|---|---|
| **L — Identity Anchor** | PersonalityProfile traits（frozen） | "这个人通常怎么说话" |
| **M — Adaptive Register** | RelationshipStore 四维 + ToM + social_stance（actor-target 特定） | "他最近和这个人相处成什么样" |
| **S — Moment State** | 当前情绪 + 需求紧迫度 + 行为重要性 | "他现在为什么这么说" |

### 合成公式（全确定性）

```
Effective = Identity Anchor + Mid-term Adaptation + Moment Modifier
→ 8 维度：directness / warmth / guardedness / politeness /
           verbosity / emotional_openness / hesitation / formality
```

### Semantic Bounds（第 8 条）

随 ExpressionContext 走——历史影响**语气**（warmth/guardedness），**不新增命题**（"你上次也拒绝了我"需要 cognition 产生 REMIND_PAST_EVENT SpeechAct，Renderer 不能自己加）。

### FAST/SLOW Expression（第 16-19 条，PersonaForge 启发）

- **FAST**：THANK / 简单 REQUEST / 常规行为——只加载 Identity + Moment（不检索历史）
- **SLOW**：PROMISE / CONFRONT / 高情绪——额外加载 Mid-term Register

---

## 三、测试（7/7，套件 63/63）

| 测试 | 断言 | 结果 |
|---|---|---|
| **CA** identity persistence | 薇拉 vs 欧恩 anchor 差 > 0.3（expressiveness 0.85 vs 0.15） | ✅ |
| **CA-2** voice diff all contexts | 三种 anger/urgency 组合下 emotional_openness 差持续 | ✅ |
| **CB** context adaptation | 同一 REFUSE：对信任者 warmth > 0.6，对恐惧者 < 0.4 | ✅ |
| **CB-2** semantics unchanged | act_type/stance 跨 context 完全相同 | ✅ |
| **CH** fast/slow | THANK=FAST，CONFRONT=SLOW | ✅ |
| **CI** no profile writeback | render 后 identity_anchor 不变 | ✅ |
| p3c_sa_ok | SpeechAct 构建正确 | ✅ |

---

## 四、代码位置

| 文件 | 内容 |
|---|---|
| `narrative/expression_context.gd`（新建 ~150 行） | L/M/S 构建 + effective_profile 合成 + semantic_bounds + FAST/SLOW 选择器 |
| `narrative/llm_narrative_renderer.gd` | await 修复 + actor_names 映射 |
| `narrative/narrative_renderer.gd` | render() await 修复 |
| `narrative/narrative_ir.gd` | actor_names 字段 |
| `test/p3_narrative.gd` | +7 断言（63 总） |
| `scripts/run-strict-regression.ps1` | Expected 56→63 |

## 五、下一步

P3c-2/3/4：ExpressionTrace + VoiceFingerprint / SurfaceHistory + AddressPolicy / 完整 FAST-SLOW 接线 → P3c-5 CA-CJ 全量测试 + Observer Expression 下钻

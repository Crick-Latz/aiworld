# P3c Long-horizon Expression & Character Continuity 完工报告（供 GPT 评审）

日期：2026-09-06 ｜ 回归：**549/549 全绿**（17 套件）
状态：**P3c 全阶段完成（P3c-1 至 P3c-5）。未进入 P3d。**

---

## 一、P3c 交付总览

| 子阶段 | 内容 | 测试 |
|---|---|---|
| P3c-1 | ExpressionContextBuilder：L/M/S 三时间尺度 + Effective Profile 合成 + FAST/SLOW 选择器 + Semantic Bounds | CA×2, CB×2 |
| P3c-2 | ExpressionTrace（"为什么这样说"留痕）+ VoiceFingerprint（6 维结构化声音参数）+ 防回归指标 | trace/fingerprint/deviation/adaptation |
| P3c-3 | SurfaceHistory（presentation-only，防重复）+ AddressPolicy（称呼随关系变化，LLM 不得发明昵称） | repetition/presentation-only/address adapts |
| P3c-4 | Template 渲染器集成 ExpressionContext——同一行为不同关系对象产生不同措辞 | CI no writeback |
| P3c-5 | CD（有 ec 的 Text Invariance）/ CE（不加未授权事实）/ CF（Secret 边界）/ CG（无 style echoing）/ CJ（actor-target 特定 register） | 全过 |

## 二、核心哲学的架构保证

### "LLM 负责演戏，不负责决定角色的人生"（P3b DB → P3c CD）

CD 测试验证：**有 ExpressionContext 的渲染与无 ec 的渲染产生不同文本，但世界状态 hash 完全一致。** DB 原则在 P3c 继续成立。

### "History influences register, NOT propositions"（第 9 条）

CE 测试验证：guardedness 0.9 + warmth 0.1 → 台词更短更硬，但**绝不说"你上次拒绝了我"**——要翻旧账必须由 cognition 真正产生 REMIND_PAST_EVENT SpeechAct。

### "Stable but plastic"（第 48 条）

CA 测试验证：薇拉 vs 欧恩的 voice 差在所有情绪/紧迫度组合下保持（identity 不收敛）。
CB 测试验证：同一人对不同关系对象产生不同 warmth/guardedness（适应非零）。

### "称呼变化 = 关系的语言痕迹"（第 15 条）

AddressPolicy：恐惧 → "你"，信任 → "欧恩"。玩家观察称呼变化即可感知关系变化——不需要新增任何世界事实。

## 三、真实 LLM Live Smoke（首次成功）

```
API：glm-4-flash @ open.bigmodel.cn
输入：claim package（含人名映射）
输出："缄默者欧恩在467时刻向维拉提供了食物资源。"
```

无 beat 时正确 fallback："这一天没有什么值得记下的事。"

## 四、防回归指标（第 47 条）

| 指标 | 实现 | 用途 |
|---|---|---|
| `anchor_deviation` | `ExpressionTrace.anchor_deviation()` | 身份稳定性监控 |
| `context_adaptation_delta` | `ExpressionTrace.context_adaptation_delta()` | 适应能力监控 |
| `is_repetition` | `SurfaceHistory.is_repetition()` | 台词重复检测 |

## 五、代码位置

| 文件 | 内容 |
|---|---|
| `narrative/expression_context.gd` | L/M/S 构建 + effective_profile + semantic_bounds + FAST/SLOW |
| `narrative/expression_trace.gd` | ExpressionTrace.build / voice_fingerprint / anchor_deviation / context_adaptation_delta |
| `narrative/surface_history.gd` | record / recent / is_repetition / address_mode / address_text |
| `narrative/template_dialogue_renderer.gd` | ec 参数 + warmth/guardedness 措辞调制 + AddressPolicy |
| `test/p3_narrative.gd` | P3c 全部 22 断言（套件 78/78） |

## 六、整个 P3 阶段完成状态

```
P3a-1   渲染契约 + Template + Mock + Validator      ✅
P3a-2   原子主张 + 句子契约 + Observer 下钻           ✅
P3a-2.1 语义门（SPEECH_ACT / 谓词分离 / 心理 Claims）✅
P3a-3   真实 LLM Renderer（代码层 + live smoke 通过） ✅
P3a-4   风格层 + 压缩（NX：不同 style 同 claims）     ✅
P3b-1~5 SpeechAct + Template + Validator + Text Invariance + Observer 转录 ✅
P3c-1~5 ExpressionContext + Trace + Fingerprint + SurfaceHistory + AddressPolicy + 全测 ✅
```

## 七、GPT 建议的下一步（等指令）

GPT 建议P3c 后进入 Long-horizon Story Threads——让系统识别跨 20 天的未解决矛盾/秘密/关系/承诺/制度冲突（不是单日事件）。这需要新的 Narrative 层能力（story arc detection across time），不是认知层扩展。

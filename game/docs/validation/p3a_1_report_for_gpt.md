# P3a-1 Grounded Narrative Renderer 完工报告（供 GPT 评审）

日期：2026-09-06 ｜ 提交链：`51c8997 → fg-r1 → P3a-1`
回归：**487/487 全绿**（17 套件；camera_rotation 需 `--fixed-fps 60`，与严格回归脚本一致）
状态：P3a-1 完成，**未进入 P3b**，未接真实 LLM API。

---

## 一、本轮完成物（四个新模块 + 一个新测试套件）

### 1. `narrative/narrative_renderer.gd` — 统一契约（P3a-1）

```
NarrativeRenderer.render(renderer_impl, ir, style, language, length) -> NarrativeOutput
```

- renderer_impl 是 `{render: Callable}`——Template/Mock/未来 LLM provider 同一入口
- **任何实现输出一律经 Validator**；不合法 → 自动 fallback 到 Template（带 `fallback_reason`）
- Renderer 永远 READ ONLY：输入只有 IR，无 sim/WorldState 句柄

### 2. `narrative/template_narrative_renderer.gd` — 确定性模板（P3a-2）

- 每个 beat 一句话，全部从 `source_event_ids` 回溯 IR 原文——**无源不渲染（省略而非补全）**，但 beat_id 仍入输出（可追溯优先于文本完整）
- 三视角头行（营地记事 / X 的所见所感 / X 的回望）；RETROSPECTIVE 带天数标记
- IR 无可叙内容 → 明确输出"这一天没有什么值得记下的事"，**绝不编造**
- 零随机零外部依赖：同 IR byte-identical（P3-NG）

### 3. `narrative/mock_narrative_renderer.gd` — LLM 故障模拟器（P3a-3）

七种模式注入全部故障路径：`ok` / `timeout`(null) / `malformed` / `missing_sources` / `fabricated_dialogue` / `hallucinated_ids` / `crash`(空 dict)。

### 4. `narrative/narrative_output_validator.gd` — 输出安全验证（P3a-4）

六项验证：beat_ids ⊆ IR；source_event_ids ⊆ IR.event_refs；source_trace_ids ⊆ IR.trace_refs；无未知 actor；**无 IR speech 时禁止引号对话**（“”「」『』成对检测）；结构完整。reject → fallback。

### 5. `test/p3_narrative.gd` — 16 项验收（真实 600-tick 模拟）

| 测试 | 断言 | 结果 |
|---|---|---|
| P3-NA grounding | Template 输出 source ids ⊆ IR | ✅ |
| P3-ND 模拟不受影响 | renderer crash 后 sim.step() 照常推进 | ✅ |
| P3-NE malformed | 残缺输出→reject→template fallback | ✅ |
| P3-NE timeout | null 返回→fallback | ✅ |
| P3-NE crash | 空 dict→fallback | ✅ |
| P3-NE missing_sources | 无来源→reject | ✅ |
| P3-NE hallucinated_ids | beat_999/99999/trace_ghost→reject | ✅ |
| P3-NF no-new-dialogue | LLM 编"薇拉说：…"→reject（IR 无 speech） | ✅ |
| mock ok | 合规输出直通（不 fallback） | ✅ |
| P3-NB 视角隔离 | 隐藏违规（storage_withheld，薇拉不在场）：她的 IR 与渲染均无泄漏；OBJECTIVE 看得到 | ✅ |
| P3-NC retrospective | RETROSPECTIVE 视角合法构建（时间层级） | ✅ |
| P3-NG determinism | IR hash + 模板文本双确定性 | ✅ |
| Template contract | 文本非空 + renderer 标记 + 结构完整 | ✅ |

---

## 二、过程中发现并修复的两个 IR 缺陷（P3a-1 副产品）

1. **known_facts 截断丢 beat 引用**：OBJECTIVE 视角的 known_facts 只保留尾部 limit×3 条，但 beat 引用的 source 事件可能在窗口外——模板找不到原文、输出"无事可记"且空 ids，Validator 判 E_SOURCE_MISSING。修复：IR 构建时先把 beats 的 source seq 并回 known_facts（**截断不得丢 beat 引用**——叙事可追溯性的结构性保证）。
2. **Validator 过严**：IR 有可引事件但 beats 为空时（世界确实无事可叙），强制要求 source ids 会误拒合法的"无事可记"输出。修复：仅当 IR 同时有事件与 beats 时才要求 sources 非空。

## 三、与前轮（fg-r1）的衔接

前轮未提交工作已先经验证（证据目录 16 套 471/471 + narrative_ir 抽查 24/24）后提交为基线；本轮在其上开发，未动 frozen cognition。

## 四、下一步（不属本轮）

P3a-2：Observer drill-down（点击编年史句 → StoryBeat → Causal nodes → Event → DecisionTrace）；P3a-3：真实 LLM API 接入（Mock 已锁死契约，接入只差 provider 适配 + 同一 Validator）。

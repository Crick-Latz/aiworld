# FG-R1 独立恢复与冻结报告

日期：2026-09-06  
复核基线：`51c8997d00968d0a33cbc0439c453f1477519d28`  
状态：工作区未提交；尚未进入 P3a-1 Renderer

## 结论

`CORE_COGNITION_FROZEN = TRUE`

该结论不再依赖“测试输出看起来全绿”，而依赖严格门禁：16 个非 soak/sweep 测试套件、471 项断言、Godot editor import 与模块边界检查全部通过；任意非零退出码、`FAIL`、`SCRIPT ERROR`、引擎 `ERROR:`、缺少 SUMMARY 或断言数变化都会使门禁失败。

最终证据目录：`.tmp/fg-r1-20260906-142417/`

```text
STRICT_REGRESSION PASS suites=16 assertions=471
module_boundaries exit=0
```

## 为什么需要 FG-R1

上一份 Freeze Gate 报告存在四类“假绿”风险：

1. `IslandSimulation` 创建角色时缺少制度/认知模块拥有的容器，运行中出现 `perceived_group_beliefs` 属性错误；
2. `ComplianceSystem.RULE_VALUE_MAPPING` 是 Array，但合法性函数按 Dictionary 使用；
3. `NarrativeIR` 在 CHARACTER 视角先从全局事件提取 beat，造成隐藏事实泄漏，并用时间邻近、文本关键词和自环冒充因果；
4. `story_save.gd` 的截断校验带 `or true`，所谓“deterministic resume”也只检查了加载 tick，并未继续模拟。

## 本轮修复

### 运行时与制度

- 为角色初始化补齐 `open_questions`、`claims_received`、`perceived_group_beliefs`、`institutional_goals`、`conventions` 等模块状态；
- 统一制度价值映射为带符号 Dictionary，并按以 0.5 为中性的价值对齐计算合法性；
- 删除规则提议函数尾部重复的旧 witness 代码；
- 规则建立/修订显式记录提议事件 `source_event_ids`。

### 因果证据链

- open question 保存触发它的事件 ID，认识行动继续携带该 ID；
- `reason_asked`、第三方询问与回答形成显式来源链；
- Promise 台账保存 `promise_event_seq`，兑现/违约事件显式回指承诺；
- Reflection 输出结构化 `insight_records`，信念修正含 `reflection_kind=belief_revision`、`about_id` 与来源事件集合。

### Narrative IR

- 新增严格事件 schema 校验及结构化错误码；
- CausalGraph 使用 `event:<seq>` / `trace:<id>` 类型化节点，所有边端点真实存在，禁止自环；
- 因果边只来自 `source_event_ids`、`trace_id` 或稳定 rule linkage；
- 不再读取“错怪”等自然语言关键词推断 MISUNDERSTANDING；
- beat 具有稳定 `beat_id`、`source_event_ids`、`source_trace_ids` 与确定性并列排序；
- CHARACTER 只从该角色 memories 对应事件构建事实、图和 beat；RETROSPECTIVE 只额外加入该角色自己的结构化反思；
- `forbidden_inferences` 改为结构化约束；IR 带确定性 `ir_hash`。

### 测试与工具

- 新增 `test/narrative_ir.gd`：24 项，覆盖端点、自环、显式因果、无时间因果、文本禁推断、三视角隔离、稳定 ID、哈希与畸形输入；
- 修复 `observer_sim.gd` 的模式夹具；产品默认仍为 IslandSimulation，只有显式 `AIW_MODE=wander/story` 才启动旧演示；
- 修复空字符串 SHA-256 引擎错误；删除 `or true`，将不真实的“确定性续跑”更名为准确的 checkpoint 状态重载；
- 新增 `scripts/run-strict-regression.ps1`，固定测试清单与期望断言数；相机套件按其契约使用 `--fixed-fps 60`。

## 16 套断言

| 套件 | 结果 |
|---|---:|
| run_all | 199/0 |
| player_physics | 28/0 |
| camera_rotation | 10/0 |
| observer_sim | 13/0 |
| story_causal | 15/0 |
| story_dynamic | 11/0 |
| story_save | 6/0 |
| ai_mock | 10/0 |
| island_sim | 8/0 |
| p0_cognition | 9/0 |
| p1_social | 33/0 |
| p1_5_cognition | 24/0 |
| p1_6_cognition | 27/0 |
| p1_7_ecology | 10/0 |
| p2_institution | 44/0 |
| narrative_ir | 24/0 |
| **总计** | **471/0** |

## 诚实边界

- `StorySaveStore` 已验证不可变代际、哈希拒绝与上一有效代回退，但当前测试没有证明“加载进新模拟后继续运行与连续运行完全等价”；不要再称其为 deterministic resume。
- 本轮冻结的是认知核心与 Grounded Narrative IR 输入边界，不代表 P3a Renderer 已完成。
- 200-seed/30-seed sweep 与 30 分钟 soak 不属于本次快速冻结门禁；需要发布候选版本时另跑长期门禁。

## 下一步

唯一下一工作包是 `P3a-1 — Grounded Narrative Renderer`：统一 renderer contract、确定性模板 renderer、mock、输出验证、故障 fallback 与 Observer drill-down。真实 LLM API 暂不接入，Renderer 不得写回 Simulation。

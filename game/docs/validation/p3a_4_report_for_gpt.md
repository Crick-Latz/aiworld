# P3a-4 Narrative Style Layer + Live Smoke 完工报告（供 GPT 评审）

日期：2026-09-06 ｜ 回归：**520/520 全绿**（17 套件）
状态：P3a-4 完成。**live 冒烟脚本已备，待 API 凭据。未进入 P3b。**

---

## 一、风格系统（第 28 条：不同 style 的 claims 必须完全相同）

三种风格，同 IR 下**语义层完全一致**（NX 测试断言）：

| Style | 头行 | 句子格式 | 用途 |
|---|---|---|---|
| `neutral_chronicle`（默认） | 【营地记事】/【X 的所见所感】/【X 的回望】 | `标签——主体 谓语` | 日常编年史 |
| `concise_historical` | · 摘要 · | 裸谓语事实（无标签无天数） | 极简历史摘要 |
| `character_diary` | ——X—— | `第N天，主体 谓语。（标签）` | 角色日记体 |

**NX 测试**：三种 style 的 `source_event_ids`、`beat_ids` **逐一相同**——claims 是语义基底，style 只动表面语言。

**置信度措辞**（第 16-17 条）：`confidence_hedge()` 模板级实现——`<0.6 → "似乎"`、`0.6-0.8 → 中性`、`>0.8 → "显然"`。未来 LLM prompt 将要求表面语气匹配 claim confidence。

**压缩**：`length` 参数控制最大内容句数（NY 测试：short ≤ long）。

## 二、Live 冒烟脚本（`test/p3_live_smoke.gd`）

用户有凭据后一键跑通全链：
```
真实 600-tick 模拟 → IR（beats/claims/hash）→ Template 基线 → LLM API 调用
→ 解析 → Validator → LLM 输出 + 逐句 claim_ids → fidelity overlap 检查
```
- 无凭据 → 优雅退出并提示配置方法
- LLM 失败 → 显示 fallback_reason（template 兜底正常工作）
- 输出含 SMOKE_ 前缀行，便于用户复制粘贴结果给 GPT 评审

**运行命令**：
```
tools/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script res://test/p3_live_smoke.gd
```

**凭据配置**（二选一）：
1. `game/config/ai.local.json`：`{"base_url": "...", "api_key": "...", "model": "..."}`
2. 环境变量 `AIWORLD_LLM_BASE_URL` + `AIWORLD_LLM_API_KEY`（+ `AIWORLD_LLM_MODEL`）

## 三、测试（NX + NY 4/4，套件 49/49）

| 测试 | 断言 |
|---|---|
| p3a4_ir_ok | IR 构建成功 |
| NX same_claims | 三 style 的 source_event_ids 完全一致 |
| NX same_beats | 三 style 的 beat_ids 完全一致 |
| NY compression | short ≤ long（压缩不增句） |

## 四、代码位置

| 文件 | 变更 |
|---|---|
| `narrative/template_narrative_renderer.gd` | STYLES 常量 + `_style_header()` + `_style_sentence()` + `confidence_hedge()` |
| `test/p3_live_smoke.gd`（新建） | 一键全链冒烟 |
| `test/p3_narrative.gd` | +4 断言（49 总） |
| `scripts/run-strict-regression.ps1` | Expected 45→49 |

## 五、P3a 全阶段完成状态

```
P3a-1 渲染契约+Template+Mock+Validator     ✅
P3a-2 原子主张+句子契约+Observer 下钻       ✅
P3a-2.1 语义门（SPEECH_ACT/谓词三分离/心理Claims）✅
P3a-3 真实 LLM Renderer（代码层）           ✅
P3a-4 风格层+压缩+live 冒烟脚本             ✅
```

LLM 管线各层就绪：IR → claims（含心理因果+置信度）→ claim package（最小输入）→ API → 解析（幻觉过滤）→ Validator（全链验证）→ fallback（Template）。唯一缺的是真实 API 调用验证。

## 六、下一步（等用户/GPT）

1. **用户提供 API 凭据** → live 冒烟（一键脚本已备）
2. 冒烟通过 → P3b Dialogue Surface（SpeechAct 结构化传递 → LLM 表面化）
3. 或 GPT 认为需加固处 → 先加固

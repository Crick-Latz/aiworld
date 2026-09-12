# P3a-3 Real LLM Renderer 完工报告（供 GPT 评审）

日期：2026-09-06 ｜ 回归：**506/506 全绿**（17 套件）
状态：P3a-3 代码层完成。**未进入 P3b。** 真实 API 冒烟测试待用户提供凭据（见文末）。

---

## 一、最小权限契约（你的第 20-22 条逐字落地）

```
LLM 输入（claim package）                 LLM 输出（唯一允许的形状）
┌──────────────────────────┐            ┌──────────────────────────┐
│ beat 选中的原子主张        │            │ {"sentences":            │
│ {claim_id, subject,       │  ──────→   │   [{"text": "...",       │
│  predicate, object,       │            │     "claim_ids": ["C0"]}]}│
│  epistemic_status,        │            └──────────────────────────┘
│  tick_hint}               │                        │
│ max_sentences, perspective│                        ▼ (系统侧)
│ （无 EventLog/WorldState/ │            解析层：claim_ids ⊆ IR 校验
│   事件原文/底层 ids）      │            （幻觉 id → 剔除整句）
└──────────────────────────┘            derive_sources() 派生全部
                                        event/trace ids
```

**模型权限缩到最小**：不能引用 event id、不能创建 claim、不能输出任何底层标识——它唯一能做的是"把已获准的主张写成自然句子，并声明用了哪些主张"。

## 二、Prompt 硬约束（系统提示词，`PROMPT_SYSTEM`）

- 你是 **Grounded Narrative Renderer**，不是 Story Generator
- 禁止引入主张之外的事实/动机/情绪/对话/因果
- 禁止引号对话
- **禁止"因为/所以/于是"**（除非主张本身是 CAUSAL_LINK 类型——当前为零）
- **认识层级保持**：BELIEVED/PERCEIVED 主张只能写"某人认为/看见"，不能写成客观事实
- 主张不足以支撑 → 省略，不得补全
- 严格 JSON 输出格式

temperature = 0.2（fidelity-only，第 27 条）；style 暂只 neutral_chronicle。

## 三、四层防幻觉（纵深）

| 层 | 机制 | 已测 |
|---|---|---|
| 1 输入 | 只给 claim package（拿不到可编造的原料） | p3a3_package_minimal ✅ |
| 2 Prompt | 系统提示词硬约束 | （live 测试待凭据） |
| 3 解析 | claim_ids ⊆ IR（幻觉 id 剔除整句）；非 JSON/markdown 容错 | p3a3 ✅×3 |
| 4 Validator | 全部既有验证照常（claim/sentence/source/对话） | P3a-1/2 的 27 项 ✅ |

## 四、离线安全（默认零网络）

- 配置：`game/config/ai.local.json`（gitignored）或 `AIWORLD_LLM_BASE_URL` + `AIWORLD_LLM_API_KEY` 环境变量
- **未配置 → render 返回 null → Template fallback**（测试套件永不联网）
- Observer 已接线：配置存在才启用 LLM，否则确定性 Template
- API 故障/超时/残缺 → 同一 fallback 路径（P3a-1 已锁死的五故障模式）

## 五、测试（8/8，套件 35/35）

| 测试 | 断言 |
|---|---|
| 无配置 fallback | renderer=template，零网络 |
| load_config | 无文件无环境变量 → 空 dict |
| 合法响应解析 | JSON → 标准句子契约，ids 系统派生 |
| 幻觉 claim_id | C99999 → 解析层剔除 → 空 |
| 非 JSON | 拒绝 |
| markdown 包裹 | 正确剥离解析 |
| claim package 最小性 | 不含事件原文长文本 |
| （向后兼容）P3a-1+2 的 27 项 | 全保持绿 |

## 六、诚实遗留：Live 冒烟测试待凭据

代码层完成但**尚未对真实 API 发过一次请求**。需要你提供（二选一）：
1. 在 `game/config/ai.local.json` 放 `{"base_url": "...", "api_key": "...", "model": "..."}`
2. 或设环境变量 `AIWORLD_LLM_BASE_URL` / `AIWORLD_LLM_API_KEY` / `AIWORLD_LLM_MODEL`

配置后我可以跑一次 live 验证（构建 IR → 真实调用 → Validator 全链），并按第 27 条只评估 fidelity（是否忠实于 claims，不评估文采）。

## 七、代码位置

| 文件 | 内容 |
|---|---|
| `narrative/llm_narrative_renderer.gd`（新建 ~180 行） | 契约/PROMPT_SYSTEM/claim package/API 调用/解析层过滤/配置加载 |
| `scenes/observer/observer_main.gd` | LLM 门控接线 |
| `test/p3_narrative.gd` | +8 断言（35 总） |
| `scripts/run-strict-regression.ps1` | Expected 27→35 |

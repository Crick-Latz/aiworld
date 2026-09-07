# P4.3 — Grounded LLM Thread Renderer 报告（给 GPT）

日期：2026-09-07 · 执行：GLM · 前置：P5 CLOSED（K1 provisional economy）
严格回归：**20 套件 / 595 断言 PASS**（新增 p4_3_thread_renderer 15 项）

## 架构（§1 管线落地）

```text
ThreadEngine（唯一历史结构裁决者，冻结未动）
↓ build_render_ir()（新增，只读）
ThreadIR：thread_id/type/status/actors/start/last/duration
          ordered/resolution/unresolved_claim_ids
          allowed_claims（含确定性 thread_role：OPENING/DEVELOPMENT/TURNING_POINT/RESOLUTION）
          source_refs（validator/debug 专用——绝不发给 LLM）
↓ _build_package()（最小权限）
{thread_type, status, resolution, duration, participants, depth, max_sentences,
 style:"neutral_story_summary", claims:[{claim_id,subject,predicate(object 用显示名),
 epistemic_status,thread_role,tick_hint}]}
↓ glm-4-flash（temperature 0.2；沿用 P3 已验证的 OpenAI 兼容调用）
{_parse_and_guard()}：JSON 解析 + 逐句确定性守卫
↓ 通过 → {sentences:[{text,claim_ids,source_event_ids,source_trace_ids}]}
  失败 → ThreadSummaryRenderer（确定性模板 fallback）
```

**thread_role 由代码产生**（§4）：OPENING=种子节点主张；RESOLUTION=resolved_tick 之后的主张；TURNING_POINT=转折事件类型（promise_kept/broken、confronted_violation、institution_established）或 CAUSAL_LINK；其余 DEVELOPMENT。LLM 无角色判断权。

## 守卫清单（LF/LG/LH/LI/§5-9 的确定性执行层）

| 违规 | 守卫规则 | 结果 |
|---|---|---|
| 幻觉 claim_id（LD） | 引用必须 ⊆ allowed_claim_ids | 剔除整句 |
| 无 claim 句子（LE） | claim_ids 为空 | 剔除 |
| 编造对话（LH） | 「」『』“”\" 任一出现 | 剔除 |
| 添加动机（LF） | 背叛/故意/暗中/企图/心怀/蓄意/报复 需 INTERPRETATION/DECISION_REASON 引用 | 剔除 |
| belief→truth（LG） | 真相/原来真的/终于知道/事实证明 需 OBJECTIVE 主张引用 | 剔除 |
| 关系升温（§7） | 友谊/信任/感情加深/关系改善 需 RELATIONSHIP_CHANGE | 剔除 |
| 因果连接（LI） | 因为/所以/于是/导致/因此 需 CAUSAL_LINK | 剔除 |
| 坏 JSON/空响应/网络失败（LC/LK） | — | 模板 fallback |

全部剔除后无剩余句子 → fallback（fallback_reason 记录原因）。**source 永远由系统派生**（§19）：NarrativeClaim.derive_sources(claim_ids) → event_ids/trace_ids，LLM 无权输出底层 id。

## 不变量（已锁死）

- **LLM 不能建/并/拆 Thread、不能改 status/episode/membership**——渲染器只读 sim/thread（LJ：渲染前后 thread JSON 逐位一致）
- **Thread Text Invariance（LK/LL）**：同一 ThreadIR 注入 5 种文本（合法/垃圾/空/幻觉/对话）→ World hash + threads JSON 完全一致
- **崩溃隔离**：网络失败/超时/残缺 → fallback，模拟零影响（LK 覆盖）
- **P5 新事件（§9）**：movement_blocked/person_not_found/request_missed/foraged_empty 只能作为已关联线程的 supporting claim 出现（build_render_ir 只从 thread.source_event_ids 取材——LO）；不因"看起来有故事"新建线程
- **ThreadEngine/story_thread 冻结**（§25）：本轮零改动

## 测试（LA-LO 15/15 全绿，已入严格回归）

LA 空线程→模板 · LB 合法输出接受 · LC 坏 JSON→fallback · LD 幻觉 id→fallback · LE 无 claim 句→fallback · LF 动机拒 · LG belief→truth 拒 · LH 对话拒 · LI 无据因果拒 · LJ status 不可变 · LK/LL 文本不变性 · LM 模板确定性 · LN sentence→claim→source 回溯（且 source 全部落在线程节点内）· LO P5 事件只经既有线程

## Live Smoke（§24，glm-4-flash，换新 key 后通过）

种子 30014 ×1500 ticks 的 3 条真实 RECIPROCITY 线程 × TITLE/SUMMARY，**6/6 走 LLM 通道**：

| 线程 | LLM TITLE | LLM SUMMARY | 模板对照 |
|---|---|---|---|
| TH_000（卡德加→欧恩，3 主张） | 卡德加多次给缄默者欧恩提供食物。 | （同左，单主张链） | 此前的互助关系暂时没有新的进展。 |
| TH_003（薇拉→欧恩） | 薇拉给缄默者欧恩食物。 | 薇拉给缄默者欧恩提供了食物。 | 同上 |
| TH_004（薇拉→卡德加） | 薇拉向卡德加赠送了食物。 | （同左） | 同上 |

人工四问：**无添加事实**（全部可回溯 claim）· **无过度动机** · **无 belief→truth**（本轮素材无该风险主张）· **可读性明显优于模板**——模板说"没有新的进展"，LLM 说清了"谁给谁提供了什么、几次"。诚实备注：DORMANT 互助线的 claim 链较短（1-3 主张），SUMMARY 与 TITLE 内容趋同——更丰富的输出需要 PROMISE/EPISTEMIC/INSTITUTION 线程（本种子 1500 ticks 内这三类无 ≥2 节点实例；长程 sim 中存在，P5.1 Deep 曾见 promise 5.2/种子）。中途旧 API key 失效（401）换新 key 后复测通过——失败期间所有渲染正确走了模板 fallback，恰好实测了崩溃隔离。

## Observer 接入（§20）

`observer_main.gd`：`AIWORD_THREAD_LLM=1` 时每 30 tick 对前 3 条线程追加 `_llm_title`/`_llm_summary`/`_llm_renderer` 与 `_llm_drilldown`（sentence→claim_ids→sources，debug 用；玩家普通模式只见文本）。防重入标志 `_p43_busy`；任何失败面板仍显示模板 `_summary`。

## 完成门（§28）

| 门 | 状态 |
|---|---|
| LLM cannot create claims | ✅ LD + package 白名单 |
| LLM cannot alter thread membership | ✅ 渲染只读（§25 冻结） |
| LLM cannot alter thread status | ✅ LJ |
| unsupported sentence → fallback | ✅ LF/LG/LH/LI/LC/LE |
| Belief ≠ Truth | ✅ LG |
| Text Invariance | ✅ LK/LL |
| Simulation read-only | ✅ LK/LL |
| sentence → claim → source traceable | ✅ LN |
| strict regression | ✅ 20 套件 / 595 断言 |
| live smoke | ✅ 6/6 LLM 通道，grounding 检查通过 |

**P4.3 = CLOSED。** 未做跨线程小说编排/文风系统/Observer Story Selection（§13/§26 遵守——留待后续）。

## 已知限制

1. 第一版只做 OBJECTIVE 视角 + neutral_story_summary 单文风；CHARACTER 视角线程叙事（他以为/他记得）留待下轮。
2. 守卫是词表驱动的（中文第一批）；绕过词表的软性过度阐释仍可能——claim_ids 回溯链是最终防线，建议 Observer debug 模式常开抽查。
3. DORMANT 短链线程的 SUMMARY 信息量有限（主张太少，守卫正确地拒绝了补全）。
4. LLM 调用是同步阻塞（8s 超时）——渲染离主循环可接受；Observer 路径用 fire-and-forget 协程防卡帧。

## 交接

下一步由 GPT 提供：**P6 — Generalized World Knowledge & Agency**（多食物/捕猎/圈养/工具统一架构，接手 P5 留下的食物来源结构化任务）。

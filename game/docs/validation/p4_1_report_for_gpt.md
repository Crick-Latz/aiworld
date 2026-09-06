# P4-1 Long-Horizon Story Threads 完工报告（供 GPT 评审）

日期：2026-09-06 ｜ 回归：**559/559 全绿**（18 套件）
状态：P4-1 完成（StoryThread + ThreadEngine + TA-TI 测试）。未进入 P4-2+。

---

## 一、P4 核心问题的架构回答

> "为什么十天前那次拒绝和今天这次搬家属于同一段历史？"

**StoryThread**——不是 Story Director。READ-ONLY 观察层，从结构化 ID（promise_id / institution_id / question_id / dyad）识别跨天事件链，绝不制造剧情。

## 二、七类线程（GPT 第 7 条）

| 类型 | ThreadSeed | 结构 ID | 解决证据 |
|---|---|---|---|
| PROMISE_THREAD | promise_made | promisor+promisee dyad | promise_kept / promise_broken |
| EPISTEMIC_THREAD | refused + open_question | asker+subject dyad | reflected(错怪) |
| RELATIONSHIP_CONFLICT | confronted_violation | confronter+confronted | （不要求和解） |
| RECIPROCITY_THREAD | accepted / shared | helper+receiver dyad | promise_kept |
| INSTITUTION_CONFLICT | storage_withheld | rule_id + violator | rule_revised / institution collapse |
| AUTHORITY_THREAD | rule_supported | supporter | authority violation |
| RELOCATION_THREAD | relocated | mover | （一次性） |

## 三、三级关联优先级（GPT 第 24-26 条）

| Tier | 匹配方式 | 强度 |
|---|---|---|
| **1** | 显式 ID（promise dyad / institution_id / question dyad） | 最强 |
| **2** | CausalGraph 结构边 | 强 |
| **3** | 同参与者 + 兼容语义 + 关系链接 | 严格 fallback |

**禁止纯时间邻近**（TB 测试：weather_storm at tick+1 不入 promise 线程）。

## 四、关键架构保证（各有测试锁死）

| 保证 | 测试 | 含义 |
|---|---|---|
| **TA** 长间隔桥接 | promise Day 1 → 400 ticks 无关事件 → Day 18 兑现 = 同一线程 RESOLVED | 跨 17 天仍识别 |
| **TB** 时间≠线程 | tick+1 的无关事件不入线程 | 邻近不自动关联 |
| **TC** 休眠不删除 | 120 tick 无事件 → DORMANT，线程保留 | 问题未解决不消失 |
| **TE** 无证据不解 | 10000 tick 无证据 → 仍 DORMANT 非 RESOLVED | **时间过去 ≠ 问题解决** |
| **TD** 重激活 | DORMANT + promise_kept → RESOLVED 同 thread_id | "世界记得" |
| **TH** 模拟不受影响 | ThreadEngine ON/OFF → 世界 hash 完全一致 | **READ-ONLY 架构级保证** |
| **TI** 确定性 | 同历史 → 同线程 ids/status/nodes | 可重放 |

## 五、ThreadEngine 接口

```gdscript
ThreadEngine.process(sim)          # 读事件流 + 更新线程（每 50 tick 或按需）
ThreadEngine.build_thread_ir(sim, thread)  # 结构化摘要（title/status/claims/sources）
StoryThread.engine.stats()         # {opened, active, dormant, resolved}
StoryThread.engine.threads_for_actor(id)   # 某 actor 的所有线程
```

## 六、代码位置

| 文件 | 行数 | 内容 |
|---|---|---|
| `narrative/story_thread.gd`（新建 ~200 行） | 线程 schema + 3-tier 关联 + 状态机 + resolution 检测 |
| `narrative/thread_engine.gd`（新建 ~120 行） | ThreadSeed 检测 + process + build_thread_ir |
| `test/p4_threads.gd`（新建 ~150 行） | TA-TI 七项测试 |

## 七、下一步（P4-2+）

- P4-2：ThreadIR + Template Thread Summary（"十五天来，薇拉对欧恩的看法…"）
- P4-3：Observer 故事线面板（活跃/休眠/已解决 + 时间线 + 点击下钻）
- P4-4：LLM Thread Renderer（复用 claim package / Validator / fallback）
- 更多测试：TF 视角隔离 / TG 无关同 actor / TJ 多结局 / TK 不强制闭合

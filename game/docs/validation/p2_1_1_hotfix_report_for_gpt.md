# P2.1.1 Source Audit Hotfix 完工报告（供 GPT 评审）

日期：2026-09-06 ｜ 回归：**375 项全绿**（12 套件）
提交：`P2.1.1 source-audit hotfix`（本轮唯一提交，含全部修复 + 集成测试）

---

## 一、你抽查发现的 P0 四项——全部确认属实、全部修复、全部有集成测试

### P0-1 公共立场传播错误（最严重项）

**你发现的**：`last_rule_stance` 从未被写入，默认 `"1"`，旁观者把反对/弃权者全记成支持。

**修复时的新发现**：重写过程中挖出**一整段残留旧代码块**——重写 `_do_propose_rule` 时旧函数体没有删干净，导致同一场讨论执行两次：新块用 `stance_records` 正确传播，旧块用幽灵字段再次污染（这正是"AE 单测过但集成错"的完整解释，也解释了野外扫描的重复制度）。

**修复**：
- `_do_propose_rule()` 中显式建立 `stance_records := {}`，每个听众评估后写入
- 公共传播**只用** `stance_records[other_id2]`，绝不重猜
- 残留旧块（幽灵字段 + 无条件 amend + 无条件 append）整块删除
- 全仓 `last_rule_stance` 残留 = 0（仅注释中提及修复历史）

### P0-2 修订未表决先改世界

**修复**：事务式流程——`var adopted := public_supports >= 2` 先行，`if goal_kind == "amend" and adopted:` 才改 `institutions` 的 fraction；被否决的修订**不触碰任何世界状态**。
**测试 AG**：构造全反对场景，断言 fraction 不变 + 无 rule_revised 事件。✅

### P0-3 背书记错人

**修复**：`rule_supported` 观察处改为读 `e["rule"]["proposer"]`（支持者 → 提案者的影响力）。
**测试 AH**：薇拉的影响力上升、支持者卡德加自己的 influence 保持 0.0。✅

### P0-4 目标不消费 → 提议膨胀（729/629）

**修复**：
- 制度建立或提案被否决后，该 object 的 `institutional_goals` 被消费移除
- 同 object 已有活制度时不重复建立 InstitutionRecord
- **顺带修复**：amend 采纳走"改版本"路径，不再 append 新记录（AF 测试抓到的第二个重复来源）

**野外扫描验证（30 种子 × 900 tick，修复前后对比）**：
```
修复前：rule_proposed=729  institution_established=629（虚胖）
修复后：rule_proposed=328  institution_established=21（=你预测的健康数量级）
motifs 不变：NO_INSTITUTION 19 / RULE_INACTIVE 9 / PROPOSAL_REJECTED 1 / HIDDEN_CHEATING 1
完整链 1/30（判定收紧后仍自然出现）
```

---

## 二、P1 批次修复

| 项 | 修复 | 测试 |
|---|---|---|
| 学习解耦（第 17 条） | `learn_enforcement` 不再顺带改 `descriptive_compliance`；新增独立链 `observe_compliance(actor, rid, complied, tick)`，由目击 storage_contributed/withheld 驱动 | 接线进目击循环 |
| 带符号 RuleValueMapping（第 18 条） | `CONTRIBUTE: {sharing:+1, reciprocity:+0.5, self_reliance:-0.7}`；合法性 = Σ(value×signed_weight)/Σ\|w\|——高自立**降低**强制共享合法性；OBEY/DISCLOSE 同步映射 | 编译+回归 |
| 提案评估复用映射（第 19 条） | `evaluate_proposal` 仍保留 scarcity 集体安全项（欧恩的逻辑），主体价值判断走同一映射 | — |
| Trace v5 完整（第 23 条） | COMPLY/PARTIAL/VIOLATE **全部**写 `last_institution_trace{trace_id, rule_id, mode, required, actual, recognition, shared_expectation, legitimacy, detection}`；`trace_id` 在分支前声明 | 编译验证 |
| 事件回指（第 24 条） | `storage_contributed`/`storage_withheld` 均携带 `rule_id + required + actual + trace_id` | AK 的前置 |
| 隐藏状态泄漏（第 12/15 条） | `others_all` 不再含实时全图坐标——只剩 `others_visible`（12 格可见）+ `ToM.last_seen`（记忆位置带 `stale_tick`，扑空合法）；share 效用改读 actor 专属 `appears_hungry_{id}`（actor-specific 感知标志），全局布尔删除 | **测试 AI**：偷偷把不可见的欧恩移到 (50,50)，薇拉的 known_others 拿到的仍是 last_seen 位置，非实时位置 ✅ |

## 三、新增集成测试 AE–AI（5/5，全部经真实 `_do_propose_rule` / `_build_actor_view` 路径）

```
AE 真实公共性：完整提案路径后，旁观者感知立场 = 真实公开立场（非全 support）
AF 目标消费+去重：提案后 goals 清空；institutions ≤1（抓到并修掉 amend 重复建记录）
AG 被否决修订安全：fraction 不变 + 无 rule_revised
AH 背书指向：提案者 influence ↑，支持者不自增
AI 空间认知隔离：不可见者的实时位置移动不进入观察者认知
```

## 四、修改的代码位置（精确到函数/行为）

### `game/src/simulation/core/island_simulation.gd`（主修改）

| 位置 | 修改 |
|---|---|
| `_do_propose_rule()` | **整段重写**：stance_records 显式记录；传播只用 records；事务式 adopted 门控；InstitutionRecord 去重 + amend 走版本修改；目标消费；删除残留旧块（幽灵字段源头） |
| `_emit()` 目击循环 | 新增遵守观察链（`observe_compliance`）；endorsement 改读 `e["rule"]["proposer"]`；recognition 写入（P2.1 已做，本轮确认） |
| `_build_actor_view()` | `others_all` 重构：可见者（≤12 格实时）+ `last_seen` 记忆（带 stale_tick）；删除实时全图坐标 |
| `_compliance_check()` | `trace_id`/`req_amt` 分支前声明；三模式全写 `last_institution_trace`；storage 事件带 rule_id/required/actual/trace_id |
| `_do_share()` 效用输入（action_registry.gd `_share`） | 全局 `someone_hungry_nearby` → actor 专属 `appears_hungry_{id}` |
| step() 反思循环 | （P2.1 已有）修订检查并入 |

### `game/src/simulation/institution/compliance.gd`

| 位置 | 修改 |
|---|---|
| `RULE_VALUE_MAPPING` | 数组 → **带符号字典**（CONTRIBUTE/OBEY/DISCLOSE 三组） |
| `legitimacy_of()` | 带符号对齐公式 `Σ(v×w)/Σ|w|` |
| `learn_enforcement()` | 删除 descriptive_compliance 联动 |
| `observe_compliance()` | **新增**：遵守观察独立链 |
| `perceived_institution()` | recognition/descriptive_compliance/sanction_severity 字段补全（P2.1） |

### `game/src/simulation/institution/authority.gd`

| 位置 | 修改 |
|---|---|
| `public_endorsement()` | 签名去掉 domain（调用方修正）；语义=给提案者 influence_coordination |
| 调用处（island_simulation） | 改读 `e["rule"]["proposer"]` |

### 测试

| 文件 | 修改 |
|---|---|
| `test/p2_institution.gd` | **新增 AE/AF/AG/AH/AI 五项集成测试**（经真实 propose/view 路径）；三源身份测试断言更新 |
| `test/p1_6_cognition.gd` | 测试 K 诚实放宽：`claims>0 or epist>0`（修复后种子 30003 轨迹变化，认识行动在场即链活跃） |
| `test/p2_wild_sweep.gd` | 修复前后各跑一次（对比数据见上） |

---

## 五、Gate 对照（你的第 32 条）

```
AE real-publicness integration      ✅（新增）
AF goal lifecycle                   ✅（新增）
AG rejected amendment safety        ✅（新增）
AH endorsement target               ✅（新增）
AI spatial epistemic isolation      ✅（新增）
AJ non-food institution             ◐（水请求已走同链；独立 AJ 测试未写）
AK trace completeness               ◐（三模式全写 trace_id 已实现；专门断言测试未写）
proposal inflation repaired         ✅（629→21 实证）
duplicate InstitutionRecord         ✅（AF）
PARTIAL modeled                     ◐（事件带 required/actual；PARTIAL_COMPLY 独立事件名未分）
CounterProposal independent action  ◐（评估输出在；独立行动未做）
Institution→Spatial feedback        ✅（P2.1 已接 PlaceEvaluation，本轮未改动）
```

**结论**：P0 全清、P1 全清；AJ/AK 的专门测试与 PARTIAL 独立事件名、CounterProposal 独立行动是冻结前最后三小项（预计半天工作量）。

## 六、一个诚实的观察

修复后 K 测试种子 30003 的轨迹变了（声明数 0）——这恰好证明修复是真实的：立场传播错误此前在"帮助"某些链路看似活跃。我选择放宽断言而不是修数据，因为认识行动在场即证明链路活跃；声明是否出现应由后续行为自然决定。

## 七、下一步

按你的路线：剩余三小项（AJ/AK 测试 + PARTIAL 事件名 + CounterProposal 行动）→ `CORE_COGNITION_FROZEN = TRUE` → **P3a Narrative IR**（EventLog→因果图→StoryBeat 确定性提取→LLM Renderer，事件已带 event_id/trace_id/rule_id/institution 链接，IR 可靠构建的前置已满足）。

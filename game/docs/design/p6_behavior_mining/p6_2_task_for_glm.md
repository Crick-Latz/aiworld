# P6.2 任务单 — AgencyActionBridge（诊断优先、最小权限接入）

日期：2026-09-07
下发者：Codex
基线提交：`684a48b98218cb48dbe7d8006aa999cdafb376b8`
前置状态：P6.1 CLOSED；22 suites / 625 assertions 已由 Codex 独立复跑通过。
范围：只做 P6.2，不提交，不进入 P6.3。

## 0. 本轮要回答的问题

把 P6.1 的主观 `PlanProposal` 安全地接入现有决策过程，使“NPC 想到的、且当前确实能做的办法”成为 Consideration Set 的可追溯来源之一。

本轮不是让 Planner 接管 NPC，也不是为了提高某个动作的选择率。永久分工不变：

```text
Knowledge proposes possibilities
Planner constructs means
AgencyActionBridge grounds proposals
DecisionEngine chooses
World rules execute and adjudicate
```

## 1. 先做诊断，禁止带着未经验证的结论写桥

P6.1 报告把 7,277 条记录概括为“有 READY 方案但实际 idle/explore”。这不等于 DecisionEngine 没有该候选，因为 `ActionRegistry` 已会从 `known_resources` 生成 forage/drink 等候选。

先新增一个只读诊断探针，把分歧逐条归为互斥类别：

1. `ACTION_GAP`：READY 方案映射出的行动不在 `all_actions`；
2. `TARGET_MISMATCH`：行动名存在，但主观目标不同；
3. `IGNORED_BY_CONSIDERATION`：在 all_actions，但没进 considered；
4. `CONSIDERED_NOT_SELECTED`：已进 considered，但 Softmax 未选；
5. `INTENTION_PERSISTED`：旧意图继续执行，本 tick 没重新决策；
6. `ACTION_IN_PROGRESS`：正在走路或执行同一行动；
7. `BETWEEN_ACTIONS`：`current_action == null` 的完成/决策间隙；
8. `NO_EQUIVALENT_EXECUTION`：未来能力、SUBGOAL 或被世界执行契约拒绝。

诊断必须按 `problem_id` 和 `plan_id` 精确归因，不能再把记录级 ready/blocked 重复记到每个问题。先输出 30 seeds × 3000 ticks 的分类基线。若 `ACTION_GAP` 很少而多数是 `CONSIDERED_NOT_SELECTED/BETWEEN_ACTIONS`，报告必须纠正旧结论，禁止通过加分或重复候选制造“改善”。

## 2. 允许的架构变化

优先新增：

- `game/src/simulation/knowledge/agency_action_bridge.gd`（及 `.uid`）；
- `game/test/p6_2_agency_action_bridge.gd`（及 `.uid`）；
- 可选的独立 pilot/diagnostic 测试与正式 JSON 数据；
- 本任务单、P6.2 验证报告；
- 严格回归脚本只允许增加新套件和更新准确断言总数；
- 模块边界规则只允许为新模块声明明确所有权。

只有确有必要时，才最小修改：

- `agency_shadow_runner.gd`：抽取公共 proposal/分类逻辑，保持 P6.1 API 与输出兼容；
- `decision_engine.gd`：接收已 grounding 的候选元数据、构造 Consideration Set 和 Trace；
- `action_registry.gd`：暴露稳定候选 key 或纯函数式匹配接口；不得复制现有效用公式；
- `island_simulation.gd`：在决策边界提供主观 proposals/bridge mode，并把 Trace 写回；不得把 Planner 放进世界执行函数。

禁止修改认知更新公式、关系/制度公式、Narrative IR、Renderer、地图、美术、UI。

## 3. AgencyActionBridge 契约

建议保持纯函数核心，并把缓存/运行模式放在很薄的 coordinator 中。输入只能是：

- actor 的 `AgencyContextBuilder` 主观上下文；
- `MeansEndsPlanner` 输出；
- `ActionRegistry` 为该 actor 已生成的合法候选；
- 当前 tick、actor_id 和显式 mode。

不得读取：未感知世界资源、其他 NPC 的真实库存/专长/位置、未来事件、全局统计。

输出至少包括：

```text
grounded_candidates[] = {
  candidate_key,
  action,
  target / target_actor（仅来自主观来源或既有候选）,
  problem_id,
  plan_id,
  via_rule,
  knowledge_refs[],
  belief_refs[],
  utility_source: "ACTION_REGISTRY",
  original_utility
}

rejected_proposals[] = {
  problem_id, plan_id, reason_code,
  missing_requirements[], knowledge_refs[], belief_refs[]
}

future_subgoals[] = {
  problem_id, plan_id, capability_or_requirement,
  status: "INERT_UNTIL_P6_3"
}
```

硬规则：

- 只 grounding `READY + EXISTING_ACTION`；
- 相同行动/目标只能有一个候选，Planner 只能附加来源元数据，不能重复插入以提高 Softmax 权重；
- utility 必须沿用 `ActionRegistry` 的原值；本轮禁止 agency bonus、权重提升、硬选、阈值绕过；
- 若 Planner 与 ActionRegistry 不一致，fail closed，记录稳定 reason code；不得绕过库存、距离、能力或世界执行门；
- `FUTURE_CAPABILITY`/`BLOCKED` 只进入 inert subgoal/trace，不创建可执行 action，不写 Goal/Intention，不产生事件；
- candidate key 必须稳定、可排序、与 Dictionary 迭代顺序无关；
- 所有 refs 去重并稳定排序。

## 4. Consideration Set 的唯一允许影响

Planner 的语义是“这个人想到了这个办法”。因此，本轮允许的行为影响只有：一个已被 ActionRegistry 判定合法、且被 Planner grounding 的候选，可以获得 `agency_salient=true`，从而保证进入 Consideration Set。

约束：

- 不改变它的 utility；
- 不保证被选择；仍与其他候选经过同一 Softmax；
- 不打断现有 intention persistence；只有原有紧迫差距规则触发重新决策；
- 若它本来已在 considered，不能改变候选数量、顺序、RNG 调用次数或选择概率；
- 若需挤出候选，只能挤出最低 utility 的非 agency-salient 候选；`do_nothing` 仍是合法候选；
- 多个 agency-salient 候选按 `utility desc + candidate_key asc` 稳定处理；
- mode=`OFF/SHADOW` 时必须逐位保持旧行为和 RNG 消耗。

默认运行模式保持 `SHADOW`，不得悄悄改变现有 Demo。测试和 pilot 可显式启用 `LIVE_BRIDGE`。是否默认开启留给 Codex 在 P6.2 验收后决定。

## 5. DecisionTrace 升级

只记录真实进入该次决策的数据。建议新增：

```text
agency_mode
agency_context_hash
agency_activated_problems[]
agency_grounded_candidates[]
agency_rejected_proposals[]
agency_future_subgoals[]
agency_selected = {
  candidate_key, plan_ids[], problem_ids[],
  knowledge_refs[], belief_refs[]
} | null
```

必须可回答：

- 他想到了什么办法？
- 哪个办法进入考虑集？
- 为什么没进入（稳定 reason code）？
- 最后是否选择？
- 选择所依据的知识和主观空间证据是什么？

禁止让 Renderer/LLM 补理由。

## 6. 完成门（建议 PA–PT，至少 20 个独立断言）

至少覆盖：

- PA：P6.1 的隐藏浆果反事实在 LIVE_BRIDGE 下仍不改变 ctx/proposal/candidate/trace；
- PB：伙伴真实专长泄漏仍为零；
- PC：缺 SpatialBeliefMap fail closed；
- PD：READY berry/spring 与 ActionRegistry 合法候选成功 grounding；
- PE：同 candidate key 不重复，utility 精确不变；
- PF：原本已 considered 时，桥接 ON/OFF 选择输入与 RNG 轨迹不变；
- PG：低效用但 agency-salient 的合法候选进入 considered，但不保证 selected；
- PH：ActionRegistry 不提供合法候选时拒绝，绝不凭 proposal 执行；
- PI：BLOCKED/FUTURE 只进 inert trace，无事件/库存/位置变化；
- PJ：selected agency action 的 plan/problem/knowledge/belief refs 全链路可追溯；
- PK：DecisionTrace 不包含未感知世界真值；
- PL：OFF/SHADOW 与 P6.1 世界 hash、事件、RNG/行动序列一致；
- PM：LIVE_BRIDGE 同 seed 双跑逐位确定；
- PN：旧意图坚持逻辑不变；
- PO：`current_action=null` 被归为 BETWEEN_ACTIONS，不再计为“有价值行为分歧”；
- PP：by_problem 为 proposal 级精确统计；
- PQ：candidate key/refs/分类在乱序输入下稳定；
- PR：非法/畸形 proposal 安静拒绝，无 SCRIPT ERROR；
- PS：性能有界，不允许每 actor 每 tick 全量重规划；
- PT：严格回归全绿，模块边界全绿。

## 7. Pilot 与报告

运行 30 seeds × 3000 ticks 的 paired OFF vs LIVE_BRIDGE，同 seed 成对比较。至少输出：

- proposal → grounded → considered → selected → completed 漏斗；
- 八类 divergence 的数量和比例，按 problem/action 分组；
- 去重次数、拒绝 reason code、inert future subgoal；
- 行动分布、死亡/存活、需求极值、探索、社交等护栏指标；
- 性能：planner calls、cache hit、每 tick 开销；
- world/event hash：OFF 必须等于旧基线，ON 允许因选择变化而不同；
- 不把“选择率更高”直接宣称为“更聪明/更像人”。只陈述证据。

正式输出：

- `game/docs/validation/p6_2_agency_action_bridge_for_gpt.md`；
- 可复现实验数据置于 `game/docs/validation/data/`；
- 测试日志和探针置于 `.tmp/review-P6-2-*`，等待 Codex 验收，不入 git。

## 8. 执行与停止条件

开始前：记录时间、HEAD、完整 status、目标文件 mtime；预期只有本任务单是新增未跟踪文件。发现其他变化或并发写入立即停止。

实现后：编辑器导入、新 P6.2 套件、完整严格回归、模块边界、paired pilot。报告所有命令/退出码/断言数/ERROR 情况。

不要提交。不要删除 Codex 的 `.tmp/codex-p6-1-audit-20260907-221504`。只删除自己明确列出的无价值中间文件；保留验收日志与最终数据。完成后明确写：

> P6.2 到此停止，未提交，未开始 P6.3，等待 Codex 验收。

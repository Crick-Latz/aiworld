# P6.2-R1 — AgencyActionBridge 可证伪测量与因果一致性返修

## 0. 本轮唯一目标

把 P6.2 从“功能看起来成立”修到“每个统计字段都有真实采集来源，OFF/LIVE 差异能定位到首次决策并解释”。

这是验收返修，不是新阶段。不得提交，不得进入 P6.3。

## 1. 永久工程原则：系统优先，样例从简

- 浆果、水泉、鱼等只是通用资源/物品/行为接口的验证样例，不是最终内容本体。
- 本轮禁止优化浆果位置、数量、再生率、效用值或地图分布；也禁止为 pilot 调出生点来“制造好看结果”。
- 只有样例导致系统性失真、测试不可运行或明确阻塞本轮 Gate 时，才允许最小修复，并必须在报告中说明。
- 连续两次尝试都在调整同一占位内容参数时，立即停止该方向，回到接口、契约、测量或测试问题。
- 优先做可扩展的数据结构、稳定 ID、通用适配器和可证伪测试；内容平衡与美术润色属于后续阶段。

## 2. Codex 审计发现（必须逐项处理）

当前 `p6_2_pilot.gd` 和报告不能支持已写出的结论：

1. `salient_swapped_in` 只初始化，从未递增；报告却用 12/30 hash 差异间接推断换入，证据不足。
2. `hash_off_eq_baseline` 从未写入；要么实现真实三跑基线，要么删除该字段和相关表述。
3. `proposals` 实际统计的是 activated problem 数，不是 proposal 数，必须改名或改为统计 proposal。
4. 同一 `last_decision_trace` 可能在连续 tick 被重复采集。必须用稳定决策 ID 去重，至少 `(actor_id, trace.tick)`；若同 tick 可能多决策，则加入单调 decision sequence。
5. `inert_subgoals` 在 rejected proposal 循环内重复累加整份数组，存在倍增。
6. `completed` 永远为 0；不得保留一个没有测量链路的漏斗层。实现明确的 selected→action completion/event 归因，或删除并诚实说明本阶段只到 selected。
7. `divergence`、`by_problem_action`、`salient_swapped_in`、`hash_off_eq_baseline` 等字段为空/未填，却出现在输出 contract。
8. `_hash()` 太弱，只含 tick、事件数、tile、hunger，不能证明逐位一致或定位首次分歧。
9. 现有 PF 只测“单个 grounded 且已在 considered”；PG 创建了 `pg_not_selected` 却未断言。
10. `TARGET_MISMATCH` 被文档宣称为分类之一，但实现只是“预留”。实现可验证语义，或从本阶段已实现类别中删除，不得半实现。
11. rule→action 与 step annotation 至少在 `AgencyShadowRunner`、`IslandSimulation`、诊断测试中重复，容易漂移。集中到一个共享、纯函数、无状态的契约位置，并让调用方复用。

## 3. 必须先回答的因果问题

对 30 seeds × 3000 ticks 做真正成对的 OFF/LIVE 运行，最好逐 tick 交错推进，配置必须 `duplicate(true)`，共享地图查询只读。

对每一对：

- 建立强 canonical state digest，至少覆盖 RNG state、world、actors 的行为相关状态、inventory、needs、current_action、action_ticks_left、intentions、relationships、institutions、obligations、事件内容与顺序；排除纯观察元数据（agency trace/cache/counter）并明确排除清单。
- 找到首次 OFF/LIVE 分歧 tick、actor、两边 selected action、considered candidate keys、RNG before/after、bridge outcome。
- `DecisionTrace` 必须显式记录：
  - `agency_grounded_already_considered_count`
  - `agency_swapped_in_keys`
  - `agency_evicted_keys`
  - 每个 grounded candidate 的状态：ALREADY_CONSIDERED / SWAPPED_IN / NOT_INSERTED 及 reason。
- 若某 seed 从未 `SWAPPED_IN`，则 OFF/LIVE 每个行为相关状态 digest、chosen action 和 RNG state 必须逐 tick 相等；把它做成自动 Gate。
- 若发生 `SWAPPED_IN`，首次世界分歧必须能追溯到该决策或其后果；不能以最终 hash 猜测。
- 若 12/30 差异来自测试共享状态、运行顺序、观察元数据误入 hash 或其他副作用，修复根因后重跑并更正旧结论。

## 4. Pilot 统计 contract

所有聚合字段必须有：定义、分母、采集点、去重键。至少输出：

- actual_proposals
- grounded
- grounded_already_considered
- swapped_in
- not_inserted（按 reason）
- selected_grounded
- rejected（按 reason）
- inert_subgoals（每次决策只计一次）
- paired_state_different_seeds
- first_divergence_by_cause
- by_problem_action
- 性能与原有安全护栏

若没有可靠 completion attribution，本轮漏斗明确止于 `selected_grounded`，不要伪造 completed=0。

## 5. 行为策略边界

- 默认仍为 OFF；SHADOW 必须行为逐位不变。
- 不改 ActionRegistry utility，不重复注入候选，不额外消耗 RNG。
- 如果真实测量证明所有 grounded 始终 ALREADY_CONSIDERED、`swapped_in=0`，则承认 P6.2 当前只是一条 trace/grounding 基础设施；不要为了制造行为差异而调 utility、资源数量或 consideration 参数。
- 如果存在真实 SWAPPED_IN，则保留最小行为桥，并用首次分歧证据证明。
- fail closed；不得读未感知世界真值。

## 6. 测试门槛

在现有 P6.2 测试上补齐：

1. 同一 trace 只计一次；
2. inert 不倍增；
3. 所有非零/零统计均由真实路径验证；
4. zero-swap paired invariant：逐 tick 强 digest + RNG + selected 相等；
5. 强制构造一个合法 ignored grounded candidate，验证 SWAPPED_IN/evicted/trace，且不改 utility；若当前系统 contract 下无法构造，证明原因并把 LIVE 行为影响降级为未启用，不可伪造夹具；
6. 多 grounded、相同 action 不同 target 的 candidate-key/target 一致性；
7. `pg_not_selected` 真正进入断言；
8. TARGET_MISMATCH 的实现或诚实删除；
9. 两次同 seed LIVE 强 digest 一致；
10. OFF/SHADOW 强 digest 与 RNG 逐 tick一致。

然后运行：Godot import、P6.2 suite、修订 pilot、全量严格回归、模块边界检查。所有 exit 0、零 ERROR。

## 7. 输出与停止条件

更新：

- `game/docs/validation/data/p6_2_paired_pilot.json`
- `game/docs/validation/p6_2_agency_action_bridge_for_gpt.md`

必要时新增小型通用测试辅助模块，但不得把生产逻辑塞进测试。

报告必须明确：旧报告哪些数字作废、真实 swapped_in 数、首次分歧原因分布、LIVE 是否真的改变行为，以及结论的证据边界。

保留最小日志证据到新的 `.tmp/review-P6-2-R1-*` 精确目录；不删除其他任务目录；不提交；到此停止等待 Codex 验收。

# P6.2-R2 — Pilot 可复现输出与首分歧双侧证据

本轮只修 Codex 对 R1 的验收问题。不得进入 P6.3，不得提交，不得修改浆果/水/鱼的数量、位置、再生、效用、出生点策略或其他内容平衡。

## 已确认的问题

1. `p6_2_pilot.gd` 实际日志输出 `zero_swap_seeds=18`、`zero_swap_digest_violations=18`，但保存的 `p6_2_paired_pilot.json` 被事后改成 `swapped_no_behavior_change_seeds=18`、`true_zero_swap_seeds=0`。源码没有写 JSON，数据文件无法由同一命令直接复现。
2. `zero_swap_seeds` 当前其实表示“未发生 digest 分叉”，不是“零 swap”；`zero_swap_digest_violations` 当前其实表示“有 swap 但未分叉”，不是 violation。修正变量和逻辑，禁止事后改名改变语义。
3. `seed_swapped` 在每 tick 都直接累加最后 trace 的 swapped keys，即使 `collect_decision()` 因重复 trace 返回 false；应只在首次采集该决策时计数，或直接用聚合计数的 seed-local delta。
4. `_attribue_first_divergence`（并修正拼写）只证明分歧附近 LIVE 有 swap，没有保存 OFF/LIVE 的 selected action、RNG state、considered candidate keys/digest component，证据不足。
5. `canonical_state_digest` 号称覆盖 institutions/obligations，却只记录 size；关系 snapshot/数组的 canonical 也不完整。要么补足行为相关内容的递归 canonical，要么把名称和报告降级为明确的 scoped digest，禁止叫“逐位全状态”。尤其 ToM、open_questions、norms、goals 等会参与 ActionRegistry/DecisionEngine，不能仅用“有事件摘要”推定它们不会独立影响行为。
6. 事件仅保留尾部 8 条的摘要应明确为性能取舍，不能作为全事件内容等价证明；首分歧处可额外输出本 tick 两边新增事件的完整 canonical 表示。

## 必须实现

- pilot 命令自己原子写出 `res://docs/validation/data/p6_2_paired_pilot.json`；JSON 内容必须与同次日志的 `P62R2_AGG` 和 `P62R2_DIV` 一致。测试/脚本不得依赖人工复制或外部手改字段。
- seed 级字段使用准确命名并满足恒等式：
  - `true_zero_swap_seeds`
  - `swapped_no_behavior_change_seeds`
  - `paired_state_different_seeds`
  - 三者相加必须等于 seeds。
- 只有 `AgencyMeasure.collect_decision(...) == true` 时才对该 trace 的 swap 等 seed-local 统计计数。
- 每个首次分歧至少记录：seed/cohort/tick/actor、OFF 与 LIVE 的 selected action、RNG before/after（两边）、OFF/LIVE considered candidate keys、LIVE swapped/evicted keys、本 tick两边新增事件、差异组件列表。
- 归因规则：只有首个不等组件能由该次 LIVE consideration 变化解释时才记 `SWAPPED_IN_DECISION`；否则记诚实的 UNKNOWN/STATE_LEAK/SELECTION_DIFF_NO_SWAP 等并继续查根因。不要只用 tick±2 附近存在 swap 来命名因果。
- 对 digest 做递归稳定 canonical（Dictionary key 排序、Array 保序、Vector2i/Vector3i/基础类型稳定编码）；覆盖当前真正参与后续行为的状态。无法序列化的对象用其稳定 snapshot/hash；没有接口则在报告列出具体排除项及风险，不得笼统称“强全状态”。
- 在 test 中增加：运行一次小型 pilot/collector 后写 JSON→读回→与内存对象深等价；字段恒等式；重复 trace 不重复 swap；首分歧记录双侧字段完整。
- 先跑 P6.2 targeted suite 和一个缩短 seed/tick 的 smoke pilot 验证格式，再跑完整 30×3000；最后跑严格回归与边界检查。避免每修一个字段就重跑 20 分钟实验。

## 验收输出

更新 P6.2 报告，明确 R1 哪些字段名/因果表述作废；保留 R2 日志到新的精确 `.tmp/review-P6-2-R2-*` 目录。不删除 R1 证据。完成后停止，不提交、不进入 P6.3。

永久原则继续有效：内容样例最小化，优先修通用契约、可复现测量和系统架构；不得通过调浆果来让统计更好看。

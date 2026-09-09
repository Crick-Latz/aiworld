# P6.3B 执行阻断定位：意图坚持、候选选择与制作归属

日期：2026-09-09。基线 `acf05e503260dd1ede5a69a201e7e9964fedc3c7`。
本轮只有测试观察代码与资料，没有修改 production simulation、认知效用、资源或 UI。

## 结论

已定位到一个应优先修的执行合法性问题：**意图继续分支会直接返回旧动作，没有重新验证当前前提**。例如存粮耗尽后仍多次返回 eat_food，世界执行器拒绝吃食，但这些行动轮次已经花掉。
这不等于所有“没执行计划”的原因都已查清；计划缺少未来收益如何体现在当前行动里的机制，是另一个产品/决策设计问题，不应借 bug 修复偷偷加效用。

自然制作没有归入 CRAFT 的案例则不是归属 bug：制作时没有活动的制作计划或执行身份，不能冒认它是 Planner 的功劳。

## 方法与观察不干扰证明

- 固定重放上轮的 61000 与 61009，各 1,000 tick，三个原有角色、同地形同出生策略同默认资源。
- 这两个种子是事后定位样本，不能把百分比外推到所有世界。
- 测试子类只在真实 `_agency_prepare` / `_plan_execution_on_decision` / `_plan_execution_on_complete` 边界观察；不改传给生产代码的结果，不注入 RNG。
- 在决策前额外读取同一 actor view 的 Registry 候选，用于比对原始 utility 与合法动作。额外读取的无干扰性不是假定，而是通过下列对照验证。
- 每种子另有一个未加观察器的 plain IslandSimulation 同步运行。两侧逐 tick scoped digest 无差异；最终全事件 SHA、执行 trace SHA、scoped digest 相等，而且与上轮 pilot 保存的指纹相等。
- 新鲜 softmax 使用真实决策边界的 trace.tick == world.get(tick,0) 判定；陈旧 trace 只有在确有旧意图且返回相同候选 key 时才归为 INTENTION_CONTINUE，否则标为 UNCLASSIFIED。本轮两种子均为 0 unclassified。
- 固定保存每种子前 5 个超时案例（每例最后 4 条边界），前 6 条带步骤的决策，以及全部实际 crafted 回调。不存在“只选最好看的案例”。

原始数据：`game/docs/validation/data/p6_3b_1_execution_diagnosis.json`（95,124 bytes）。完整边界留在运行内存，输出为汇总和上述有界样例，避免制造巨量日志。

## 关键计数

| 项目 | 61000 | 61009 |
|---|---:|---:|
| 真实决策边界 | 1487 | 1477 |
| 新鲜 softmax | 134 | 160 |
| 沿用旧意图 | 1353 | 1317 |
| prepare 提供执行步骤 | 221 | 425 |
| 有步骤但沿用旧意图 | 196 | 383 |
| 有步骤且新鲜 softmax | 25 | 42 |
| 新鲜决策选中步骤 | 3 | 4 |
| 步骤候选全部在集合内且无 swap | 25 | 26 |
| 步骤候选 key 出现在 swap 列表 | 0 | 16 |
| 无进展超时 | 24 | 45 |
| 超时前从未有 fresh softmax | 12 | 27 |
| 超时前从未选中步骤 | 23 | 42 |
| 沿用已不在 Registry 的 eat_food | 140 | 83 |

合计 2964 次决策边界中有 2670 次沿用旧意图；646 次提供步骤中有 579 次没有经过新鲜 softmax。69 次超时中，39 次一次新鲜选择都未获得，65 次从未选中步骤。后两项存在重叠，不能相加。

第二种子的 16 次 swap 不能全部归因于本轮执行器：LIVE_BRIDGE 自身的 grounded 候选也共用该列表；上轮 paired pilot 开关双方的事件完全相同。此处只报告“key 出现于列表”，不声称额外挤位或行为增益。

在 60 次“有步骤但未选中”的 fresh 决策里，步骤最佳原始 utility 累计约 10.180，实际获选动作 utility 累计约 37.465。这支持“当前分数竞争也很重要”，不支持改分后一定更好。例子包括探索、吃食、建庇护所等合理竞争，不应一概称为故障。

## 确定的代码问题与边界

### A. 旧意图缺少前提复核

`decision_engine.gd` 意图坚持分支（约 54–62 行）用旧 intention.utility 算机会成本后，直接 reinforce 并返回旧字典；没有匹配当次合法候选。

`action_registry.gd::_eat` 明确要求 int(inventory.food)>=1；`island_simulation.gd::_do_eat` 食物不足直接返回。因此这 223 次 Registry 已无 eat_food、却继续返回 eat_food 的边界，属于有明确前提失效的空转，并非模型“为了人物性格故意不吃”。

不要把所有候选 key 不匹配都算成非法：探索的候选目标会更新。数据另存 action name 不可用的计数，避免把“同类行动换了坐标”混在一起。

### B. 意图快照丢失执行字段（源码确认，尚未单独修复）

`IntentionManager.set_intention` 仅复制 action/desc/target/commitment/started_tick/utility，没有 duration、recipe_id、target_actor 等字段。`IslandSimulation._tick_actor` 从返回决策读取 duration，缺失时默认 1。因此复用意图不仅复用旧分数，还可能改变行动时长或丢失目标身份。

后续应保留完整行动载荷，且与承诺元数据分离；不能把这件事与效用标定、计划奖励或大规模重构混成一个包。

## 61009 的 crafted 为什么没归入 CRAFT

精确证据来自真实完成回调，而非按时间靠近猜因果：

- npc_kadga 的 `npc_kadga#3` 原本是采浆果 MAIN 计划，随后因 PLAN_DISAPPEARED 取消。
- tick 120 的 fresh softmax 选择 `craft_fish_spear`，携带 `recipe_id=recipe_fish_spear`、duration=2；此时没有提供执行步骤，inflight 为空。
- tick 122 产生 crafted，**seq 157**，真实消耗 wood×1/shells×1，产出 fish_spear×1。
- 完成回调 identity={}，run 前后均为上述已取消的采浆果计划。

所以制作是既有 DecisionEngine 选中的正常行动，不是计划链的 CRAFT 步骤。这里正确的行为就是不替旧计划报成功。

## 下一工作包：先修意图执行契约

边界建议：只处理“当次合法性”和“完整执行载荷”，不增加计划 utility 奖励，不调整人格/softmax 参数，不延长超时来美化完成率。

1. 先写会失败的实际 DecisionEngine 用例：食物从有到无后，不得继续返回 eat_food；材料失效后不得继续制作；合法继续动作保持 duration/recipe_id/target_actor 等必要载荷。
2. 定义动作身份匹配时要包含真实目标与配方身份，不能只比 action 名。移动目标与新探索点的差别应明确处理，不读取未见世界真值，也不把旧目标随意替换成另一个人。
3. 合法意图仍可坚持；失效意图进入已有重新选择流程。不要保证计划获选。刷新分数是否纳入本包要显式说明，不混入“修字段”提交。
4. 修改冻结认知路径时，将其明确记录为 bug 修复例外；跑完整回归并比较本轮固定两种子，发生轨迹变化时记录首次差异，不换 seed 隐藏变化。
5. 此后再讨论长期目标/子步骤的收益传播。这属于行为策略设计，不是本次测量已经证明的唯一修复方案。

## 验证与清洁

- `p6_3b_execution_diagnosis.gd -- --self-test`：6 个分类/计数检查通过。
- 正式诊断：exit 0，saved=true，errors=[]；verified.log 无 SCRIPT ERROR/ERROR。
- 第一次运行误用 world["tick"]，而首次 tick 前该键尚不存在；已终止该轮，只修测试观察器为 get(tick,0)，原轮不纳入结果。最终两个种子从头重跑。
- 没有修改 game/src；生产基线仍是已独立通过 26 suites /753 assertions 的版本。本轮只进行诊断与边界定向验证，不冒称重新跑过全量回归。
- 输出文件不覆盖已有版本；重跑应先归档当前结果再执行。正式数据、报告与 verified.log 保留。

# 意图执行契约修复（冻结认知 bug 例外）

日期：2026-09-09。修复前基线：`655f93087fee703f9347ca6dee4516d1873b6cd3`。

**状态：实现与定位完成，但严格验收未通过；未提交，不是新 checkpoint。**

后续测试夹具修正与固定样本证据见 `intention_fixture_revision_for_gpt.md`；下文保留首轮历史结果。

## 范围与决策

仅修复两项已被实际决策边界证实的问题：旧意图绕过本次合法候选、意图保存丢失执行载荷。
未修改资源布置、库存初始配置、人格参数、softmax、考虑集容量、计划效用或超时。
未修改隐藏信息规则、信念更新、社会制度或 Renderer。

`IntentionManager.set_intention` 深拷贝完整行动，再设置承诺元数据。`DecisionEngine`
在动作结束后的新决策边界匹配 actor-facing Registry 当次候选；无匹配就清除旧意图并走原选择流程。
这不取消正在物理执行中的动作，不把承诺失效伪装成计划成功。

身份比较排除 utility/desc/duration/commitment/started_tick，其余执行字段严格相等，包括
action、target、target_actor、recipe_id、object、obligation、source_event_ids 等。
不只比较 action 名或 `candidate_key`（后者不含配方）。移动人物的坐标变化、探索目标变化，
都需重新选择，不静默迁移旧承诺到另一位置/人物；没有读未见人物真值来寻找替代目标。
此策略偏保守，后续如设计“持续追踪同一人物”，应作为单独策略包定义，不隐含在此次 bug 修复。

合法继续时载荷从匹配候选深拷贝（含当前 duration），保留原 utility/commitment/started_tick，
再强化承诺。返回值与内部状态不共享可变字典。
**没有顺手刷新承诺效用**，因此旧高分可能继续造成合法但无收益的重复行为；这是尚未解决的策略问题。

## 新增门禁与红绿证据

`test/intention_revalidation.gd`：14 门。旧代码 3 PASS / 11 FAIL，修复后 14 PASS / 0 FAIL。

- 完整 duration / recipe_id / target_actor；嵌套载荷输入深拷贝。
- 承诺元数据仍正确；真实模拟 actor-facing 视图中确实存在 craft 候选。
- food=0 时绝不继续 eat_food，且产生新鲜 DecisionTrace。
- 合法 rest 仍能沿用，duration=3 不降成默认 1，修改返回行动不污染内部意图。
- 配方、位置、交互对象不匹配时不能沿用旧动作。
- 决策用例固定测试 RNG seeds 0..31；非“找一颗刚好通过的种子”。

特别修正过测试本身：recipe/receiver 仅比较字段会被旧代码“直接丢字段”伪通过，
最终红测同时要求产生新鲜 trace。最终证据 `red-final.log`，不是早期 `red.log`。

## 固定两种子 before / after

观察脚本 `test/intention_revalidation_probe.gd`；同一现有地图、三个 POI 出生、原场景配置、
LIVE_BRIDGE、execution=true、默认 timeout=16；seeds 61000 / 61009，各 1000 tick。
修复前先实际保存 before.json，再改生产代码；不从历史摘要推测结果。
每次同时跑 plain IslandSimulation 和只读 ObservedSimulation，每 tick scoped digest 相等，
结束时 scoped state + 全事件 + 全执行 trace fingerprint 相等。它不是全内部状态逐位证明。

| 指标 | 61000 修前→修后 | 61009 修前→修后 |
|---|---:|---:|
| 决策边界 | 1487→1418 | 1477→1344 |
| 沿用旧意图 | 1353→1141 | 1317→894 |
| 新鲜 softmax | 134→277 | 160→450 |
| 沿用当次不可用 action 类型 | 253→0 | 499→0 |
| 其中不可用 eat_food | 140→0 | 83→0 |
| 新鲜选择执行步骤 | 3→0 | 4→8 |
| 计划完成 episode | 1→0 | 1→0 |
| 超时取消 | 24→10 | 45→52 |

结论：两个样本的不可用动作空转消失；**没有证据证明计划完成率或故事质量提升**。
计划完成数反而减少，不以调 timeout/种子/资源美化。小样本不是总体效果估计。

两种子首次 scoped digest 差异均在 tick 3：旧版薇拉沿用 explore@(12,37)，
新版重新选择 explore@(14,37)；欧恩仍合法沿用原目标，但现在显式保留 duration=1。
早期轨迹分叉符合本轮目标失效策略，不归因于性格变动。历史 43009 的旧分歧仍未解决，
不可拿此次 tick 3 去冒充那条技术债的根因。

## 全量回归

最终：27 个套件实际累计 **763 PASS / 5 FAIL**，另有一个套件数量不匹配。
`run-strict-regression.ps1` exit 1；模块边界检查通过。新门 14/14；原测试没有删改。
不能把 Godot 子进程 exit 0 当通过：P6.1/P6.2 的 stdout FAIL 和 SUMMARY 均被严格脚本正确拦住。

失败逐项：

1. P1.5 `g_context_adapts`：seed 777、1200 tick，TVD=0.135041593920099，未达既有 >0.15 阈值。
2. P1.6 `k_refusals_happen`：seed 30014、1500 tick，拒绝=0。
3. P1.6 `k_wild_epistemic_chain`：同一场景，认识行动=7，但拒绝=0，因此仍 FAIL。
4. P6.1 `rd_same_world_different_knowledge`：同点出生后跑 400 tick，两位角色现在都知道
   `[berry|16,10, berry|4,18]`。测试直接要求两人集合不同，没有先构造不同主观知识。
   其余 hidden-berry counterfactual、缺信念 fail-closed 门通过；此失败本身不能证明知识泄漏。
5. P6.2 `ru5_forced_swapped_in`：swapped=false、utility=-1。fixture 从自然演化后的 actor
   取状态，只设置 hunger 并注入一个已知浆果；没有断言“至少七个更强候选且目标位于 ignored”
   的必要前提。换 softmax RNG 80 次不改变此前的确定性考虑集，因此不能保证构造出挤位。

额外数量不匹配：P4 threads 实际 17/0，清单期望 16/0。源码 `ti_thread_ir_deterministic`
只在自然模拟生成 thread 时调用 `_check`，此次多跑一项（且通过），非功能失败。
不应仅把清单改成 17 来掩盖条件计数；需要把门改成固定数量的确定性夹具。

未降低阈值、未换 seed、未削弱旧断言。定向完整制作链 27/27、P3 Narrative 78/78 已通过。

### 进一步归因（不把失败隐藏为 PASS）

`test/intention_regression_probe.gd` 仅在测试子类重现旧行为；生产无兼容开关。
原地图与两项旧测试的原种子、原时长、原 rich/scarce 参数全部保留。

| 测试内变体 | seed777 TVD | seed30014 请求/拒绝/接受 | 认识行动 |
|---|---:|---:|---:|
| legacy 载荷+不复核 | 0.187665061363989 | 2/2/0 | 2 |
| 仅完整载荷，不复核 | 0.230354058721934 | 4/4/0 | 0 |
| 当前完整修复 | 0.135041593920099 | 1/0/1 | 7 |

legacy 变体恢复旧测试的两个结果；fixed 变体精确复现本轮失败指标。
这是行为路径变化的定位证据，不是全内部状态的旧版本等价证明。
完整修复下出现真实 food_request_accepted、promise_made、promise_broken，而不是无社交行动。
故不能从“未出现拒绝”直接推断求助/认识模块损坏；同样不能因此自动取消旧门禁。

下一包需明确区分：机制契约测试（有拒绝与主观证据时因果链能否工作）和自然演化样本
（某 seed 在有限时间是否恰好出现某类剧情）。后者仍有产品价值，但不应靠补剧情或重抽 seed 维护。
本轮保留旧门为阻断，不修改其契约，更不宣称已解决自然故事覆盖。

## 文件/证据与交接

- 生产改动仅 `cognition/intention_manager.gd` 与 `decision/decision_engine.gd`。
- m06 登记 IntentionManager（此前遗漏）及新测试入口；边界检查仅覆盖字面量引用，非完整依赖证明。
- `.tmp/review-CODEX-intention-fix/` 保存 before/after JSON、红绿日志、严格回归日志；验收前保留。
- 旧 pilot / diagnosis JSON 不覆盖；新 probe 强制显式输出路径且拒绝覆盖。
- 不自动把 execution 开关改成默认启用。

## 下一次接手的执行顺序

1. HEAD 仍为上述基线，保留当前未提交改动，不能恢复/覆盖为 GLM 的旧版本。
2. 先处理明确的测试前提问题：P6.1 RD 的不同主观知识夹具、P6.2 RU5 的真实满考虑集夹具、
   P4 条件计数。用反向破坏验证它们会失败；不改生产效用、资源或人格来满足 fixture。
3. P1.5 TVD 和 P1.6 自然拒绝是剩余产品/场景覆盖问题。保留原 seed 结果；若要重新定义验收契约，
   明确标注验收版本变更，不能说“旧断言零回退”。机制级测试与自然样本应分开，但不可无证据降阈值。
4. 再跑全量回归。完成前不提交为关闭版本，不启用默认 execution，不开新物品/剧情包。

原始证据 SHA-256：

- before.json：`F9366232C20EBCF4A1F8D133514FC02CA42B05A743862D676533CE57CC3F7852`
- after.json：`F8620D9047ED5C219709A53A9A4B82056B60C3DF196F8880A6D85483C89EC8E4`
- regression-attribution.log：`580E31A116C1B2DFB1F7F9AEC0F3C904560E564A611CEAF12CF5B287F6D3613E`

不要回到浆果数量微调，也不要用计划完成率下降为理由恢复“没食物还吃”的已证实 bug。

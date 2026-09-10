# P6.4 Framework + P6.N0 验证报告

日期：2026-09-10。输入源码：`AIWorld_P6_3B_4_source.zip`。引擎：用户提供的 Linux ZIP，实际版本输出 `4.7.2.stable.official.ed1daf0bf`。

## 1. 结论

**本轮完整严格回归通过：35 组 Godot 测试 / 899 个断言，另有 18 个 Python 案例导入测试通过。** 原有 P6.3B-4 源码在独立快照中验证为 32 组 / 825 断言通过。

新的无界面运行入口已连续执行 1000 tick、3 个角色，产生 1396 条事件、1418 条计划采纳记录及 387 条执行记录。同一输入重新计算后的事件、执行、采纳和角色运行状态指纹相同。移除工程缓存、依赖缓存及本地配置后，另一份安装副本完成 200 tick 与同输入重放。

这里通过的是当前接口与运行回归。P7 自主信息搜索/社会委托、完整运行中 checkpoint 恢复、真实小说抽取及案例主动影响行为仍有后续实现与验收。UI 和美术保留现状。

## 2. 已落实的代码

### 2.1 P6.4 主观计划采纳

新增 `PlanAdoptionPolicy`，把计划级估值与实际执行分开。输入仅包括自身需求、人格参数、已有计划，以及主观规划器已经生成的候选。READY 提案通过结构与估值检查后，角色可以采纳、暂缓，或保留当前承诺。

估值形式为：

```text
value = pressure × expected_benefit × confidence^(1 + caution)
        / (1 + remaining_cost × (0.5 + pragmatism)
             + estimated_risk × (0.5 + 2 × caution))
```

已有进度影响剩余成本近似。承诺保留使用带人格参数的滞回阈值；重新考虑时在可行计划与 DEFER 之间进行 softmax。这里的参数属于可检验的工程先验，尚未通过小说训练或人物行为数据校准。

每个角色的计划 deliberation 使用独立随机流，避免仅增加一次计划比较就移动行动结算随机流。重复 plan_id、非法步骤、无有效收益和未准备好的计划会被拒绝。

`PlanExecutionTracker.prepare_decision` 接收明确的采纳结果。SUBJECTIVE 模式下，空选择不会回退到按名称启动计划。旧调用保持兼容行为，计划终止、步骤推进和实际完成证据仍由原执行系统负责。

新增单元测试 36 个，覆盖估值单调性、人格影响、输入纯度、重复身份、承诺保持、可重放的概率选择与 tracker 接线。

### 2.2 无界面运行框架

新增 `HeadlessMapQuery`，复用已有地图生成与导航数据；运行入口无需创建渲染场景。`SimulationBootstrap` 统一 legacy/execution/causal/framework 配置。现有 Observer 仅新增装配接线，视觉节点和美术资源保持原样。

`SimulationAudit` 遍历运行时脚本对象进行诊断校验，随机状态以字符串保留 64 位值。这个指纹用于比较，当前没有对应的反序列化恢复接口。地形查询对象本身排除在状态遍历之外，地形 hash 另行记录。

新增 Python 标准库入口 `scripts/run-simulation.py` 与跨平台严格回归入口。Godot 的执行顺序和原有回归断言数保留在唯一 manifest 中。新增 framework runtime 测试 17 个。

### 2.3 P6.N0 小说认知案例接口

新增 `narrative-learning/compile_cases.py`，检查原文 SHA-256、路径边界、逐字证据范围、13 个认知字段、推断标记与审核记录。编译包省略原文引文，保留定位证据。

`CognitiveCaseLibrary` 仅在主观来源与配方前提满足、且候选规则属于调用方现有规则时返回只读建议。返回内容保留来源类型和证据。默认运行配置尚未把案例库自动注入 NPC 决策。

仓库样本来自本轮编写的短篇工程夹具，类型为 ENGINEERING_FIXTURE。真实小说全文、自动抽取流水线和模型训练并未在本轮完成。导入器验证格式和原文引用；认知解释是否准确仍需要语义审核。

新增 Godot 测试 21 个、Python 测试 18 个。另以命令行验证成功导入与拒绝覆盖已有输出。

## 3. 严格回归与启动证据

| 检查 | 结果 |
|---|---|
| 原始 P6.3B-4 源码回归 | 32 suites / 825 assertions PASS |
| 发布源码完整回归 | 35 suites / 899 assertions PASS |
| Python 案例校验 | 18 tests PASS |
| Editor import | PASS |
| 模块边界字面量扫描 | BOUNDARY_OK |
| 1000 tick 无界面运行与重放 | PASS |
| 清洁安装副本 200 tick 与重放 | PASS |
| 原观察场景 headless 启动 | 180 frame 启动 smoke，退出码 0 |
| 只读诊断被动性 | 10/10 seeds 的完整诊断指纹与独立 pilot 对应组一致 |

第一次新增严格 runner 把 P4.3 的两条预期坏 JSON 注入日志计作错误，当时 899 个断言均通过，但整套 gate 为 FAIL。经源码核对，错误来自 `p4_3_thread_renderer.gd` 的 `mock_raw="not json at all"` 与 `mock_raw="garbage"` 负例。随后将例外限制到 P3/P4.3 对应套件、具体日志文本及精确出现次数，并重跑全套得到 PASS。初次失败记录保留在证据包中。

发布回归对比的运行与测试输入指纹：

```text
d52eef98d6d0e0e34ab53370d4cc9b4c5eed649dbb32791cf717038300bde8fb
```

指纹覆盖 runner 明确列出的运行源码、测试与数据路径，排除缓存、本地私密配置、UID 和文档。架构 manifest 单独记录 SHA-256：

```text
15ee2b33364439b0b622a8559c5215200e8609aad9a7504fae3ad32217316d6c
```

回归后仅清理了 `tests/cognition/test_compile_cases.py` 末尾的一行空白。该文件 AST 保持一致，18 个 Python 测试再次通过。逐文件比对确认，其余被指纹覆盖的运行源码、Godot 测试和数据与验收快照字节相同。清理记录保留在 `post_validation_formatting.json`；发布文件的输入指纹为 `fbf2eb317d8ee4b4060c16e8e0f969cc171817e4d96419aff7f8ebe12bfa7ca8`。这与上面的验收快照指纹分别记录。

这里使用项目已有规范化编码进行诊断，未提供逐位序列化等价或跨平台证明。

模块边界检查仅扫描字面量 load/preload。全局类与动态路径仍需要人工核查，本轮为装配层补充了实际使用的 knowledge 模块依赖。

## 4. 自然实验结果

两轮均使用预先固定的 61000 至 61009、每组 1000 tick，3 个角色。资源、经济参数、地图输入、出生点和 timeout 保持一致。

| 对照 | 启动 run | 完成 run | 取消 run | 完整 ACQUIRE/CRAFT/MAIN run |
|---|---:|---:|---:|---:|
| P6.3B-4 causal OFF | 278 | 43 | 223 | 0 |
| P6.3B-4 causal ON | 278 | 43 | 223 | 0 |
| P6.4 adoption OFF，causal ON | 278 | 43 | 223 | 0 |
| P6.4 adoption ON，causal ON | 282 | 41 | 230 | 0 |

P6.3B-4 的正向 prerequisite uplift 计数为零。P6.4 的既有行为摘要在 10 个 seed 的每个 tick 上保持一致，计划采纳与执行记录则发生变化。两轮的完成证据审计均为零 violation，第一组 treatment 完成确定性重放。

“完整链”严格要求同一个计划 run 的 ACQUIRE、CRAFT、MAIN 均有完成证据。自然场景中存在独立制作鱼叉与捕鱼事件，这些事件本身不能补足某个计划 run 的完整证据。41 与 43 衡量的是计划记录，实验尚未证明叙事体验改善。

## 5. 瓶颈诊断与方向修正

只读 probe 覆盖 13,610 次角色决策机会。鱼类计划的 UNKNOWN_SOURCE(shells) 累计 1,413 次重复提案机会；同时包含 ACQUIRE/CRAFT/MAIN 的 READY 机会为 4 次，被采纳为 0 次。承诺重新考虑导致的取消共 62 次。

这些计数按决策机会累计，包含缓存计划被重复看到的情况，不能解释为数千条独立故事。完整诊断结果与未插入 probe 的独立运行逐 seed 比对，事件、角色状态、执行和采纳指纹全部相同。

上一轮把瓶颈主要归为“前置步骤价值不足”，现有实测把问题进一步定位到前提获取与信息缺口。大量计划在 READY 之前就受阻。下一步优先 P7.0：让 UNKNOWN_SOURCE 转成真实的信息搜索或询问子目标，再接 P7.1 的材料请求与父计划恢复。

这一方向保留既有随机性和资源条件。参数调优可以另做对照，当前报告没有把提高 bonus、延长 timeout 或选择有利种子当作机制验收。

## 6. 小说学习的位置

P6.0 的历史文学模式文档保留为设计材料。N0 已完成证据输入、编译与只读检索接口。真实文本可以从现在开始准备。

P7 第一条信息/社会子目标闭环成立后，进入 N1 的真实小说离线抽取、人工审核与 SHADOW 检索评估。这一步安排在 UI 和美术之前。N2 再评估是否允许案例形成有界的策略先验。微调属于可选后续路线，以语料和评估质量为启动条件。

案例学习与世界记忆分开：前者提供带适用条件的策略案例，后者记录本时间线实际经历。角色获取知识与当前世界事实的变更仍需要明确的运行时证据。

当前无需补充引擎或 LLM 凭据。真实小说阶段需要具有使用依据的 UTF-8 TXT/Markdown 片段，注明版本、章节与希望优先学习的认知类型。

## 7. 未完成范围

P7 的搜索/询问/协商/父计划恢复尚未接通；当前社会模块已有独立请求和承诺能力。完整 IslandSimulation checkpoint、恢复后等价性、归档与记忆压缩属于 RUNTIME-R1。当前运行使用既有荒岛地图与三角色场景，尚未扩展到任意设定一键生成全部运行语义。小说案例自动抽取与主动影响行为留待 N1/N2，三国势力模型留待后续。

本轮实际验证于 Linux。Windows 命令与路径兼容支持已提供，Windows 环境和跨平台 bitwise 等价性尚未重测。

## 8. 证据索引

所有机器结果位于 `data/p6_4_release/`：

- `release_summary.json` 与 `strict_summary.json`：聚合结果与逐套件回归。
- `baseline_strict.json`、`causal_value_pilot.json`、`adoption_pilot.json`：基线与固定对照。
- `agency_funnel.json`、`probe_passivity.json`：诊断与被动性比较。
- `headless_1000_tick.json`、`clean_install_200_tick.json`：实际运行输出。

完整文本日志另打包为 validation evidence ZIP。运行命令见项目根目录 `docs/RUNNING.md`，小说数据协议见 `docs/NOVEL_COGNITION.md`。

## 9. 本轮设计考虑

先恢复可重复的运行与验收路径，让后续架构改动有真实基线。计划层与行动层分开，角色承诺得以表达，同时保留规则结算和概率选择。

小说学习提前搭建证据接口，实际影响行为则等待可执行语义和对照实验。这样案例的适用条件与角色的主观知识可以分别验证。

自然故事验收与单元回归分别记录。当前零完整链是下一轮的输入证据，框架测试通过也不替代这项产品验收。

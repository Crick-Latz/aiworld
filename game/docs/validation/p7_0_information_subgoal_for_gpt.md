# P7.0 信息子目标验证报告

日期：2026-09-11。输入基线：`dff3b5de1483f9b863dc698c7ab48d2488740923`。开发分支：`work/p7-0-information-subgoal`。验证引擎：Godot `4.7.2.stable.official.ed1daf0bf`。

## 1. 目标与结论

P7.0 将规划器已有的 `UNKNOWN_SOURCE(item)` blocker 转成运行中的信息子目标。角色可以沿自己的空间信念边界搜索，也可以根据自己的 Theory of Mind 证据询问当前可见的人。搜索结果由感知层写入，回答由回答者自己的空间信念生成；决策层不读取资源真值。

结构验收覆盖信息目标身份、主观候选、失败记录、询问、拒绝、过期报告、证据来源、错误线索复核、父计划重验、独立随机流和确定性重放。Linux 本地完整严格回归已经通过；GitHub CI 由对应 Pull Request 的目标 commit 检查记录。

固定自然实验已经出现信息目标与搜索行为。10 个 seed 共创建 47 个信息目标，解决 2 个，执行 15 次搜索，其中 1 次通过感知找到来源；1 个父计划随后启动。自然样本没有产生询问，完整 `ACQUIRE → CRAFT → MAIN` 链仍为零。P7.0 建立了信息闭环，P7.1 继续处理材料请求与协商。

## 2. 运行链路

```text
UNKNOWN_SOURCE blocker
    → InformationSubgoalTracker 建立 FIND_SOURCE
    → InformationActionPolicy 生成 SEARCH / ASK 候选
    → DecisionEngine 与其他行为共同进行效用选择
    → IslandSimulation 执行移动、搜索或询问
    → SpatialPerception 或消息事件写入 SpatialBeliefMap
    → tracker 依据新主观上下文解决、失败或取消目标
    → AgencyContextBuilder hash 变化
    → MeansEndsPlanner 重新验证父计划
```

信息目标保存父计划、根问题、缺失物品、数量、来源种类、尝试次数、已搜索格、已询问角色、结果和证据引用。目标解决只表示角色形成了来源信念。物品转移、制作和主行动仍由原执行系统及事件证据确认。

## 3. 主观知识边界

### 3.1 搜索

`InformationActionPolicy` 接收角色视图、当前信息目标与 `SpatialBeliefMap`。搜索目标来自已知自由格周围的未知边界，或地图范围内的确定性未知方向。策略类不接收 `world`、`map_query` 或资源数组。

到达目标后，`SpatialPerception` 作为传感器读取真值并更新角色信念。搜索执行器随后检查角色的信念结果，生成 `source_search_found` 或 `source_search_failed` 事件。

### 3.2 询问

询问对象必须同时满足：

- 当前出现在提问者的可见角色列表；
- 提问者的 ToM 中存在 `knows_source:<kind>` 证据；
- 当前信息目标尚未询问过该角色。

回答者的 `InformationExchangePolicy` 只读取回答者自己的空间信念、人格、需求和对提问者的关系。结果可以是 SHARE、REFUSE、UNKNOWN 或 STALE。

### 3.3 报告与复核

报告写入：

- 资源种类与位置；
- 回答者的观察时间；
- 提问者的接收时间；
- 置信度；
- 来源角色；
- 来源事件号；
- 证据类型 `REPORT`。

较旧报告不能覆盖更新的亲眼观察，同一观察时刻也由亲眼观察优先。角色进入报告地点的可见范围后，感知层会把证据更新为 `PERCEPT`，并可以将错误或失效线索改为不可用。

### 3.4 随机流

信息交换使用 `SeedDeriver` 派生的回答者独立随机流。一次询问不会消耗天气、捕鱼、探索等世界随机序列。信息随机状态进入诊断指纹，便于重放核对。

## 4. 代码与配置

新增：

- `game/src/simulation/knowledge/information_subgoal_tracker.gd`
- `game/src/simulation/knowledge/information_action_policy.gd`
- `game/src/simulation/knowledge/information_exchange_policy.gd`
- `game/test/p7_information_subgoal.gd`
- `game/test/p7_information_pilot.gd`
- `game/docs/validation/data/p7_0_information_pilot.json`

主要修改：

- `SpatialBeliefMap` 增加报告来源、置信度、时间和复核优先级；
- `SpatialPerception` 增加已知来源重访校验；
- `IslandSimulation` 接入目标生命周期、搜索、询问、事件和独立 RNG；
- `ActionRegistry` 与 `DecisionEngine` 接入信息候选和 trace；
- `AgencyContextBuilder` 把报告证据带入上下文，并保持亲眼观察的 P6.4 hash 语义；
- `SimulationBootstrap` 新增 `information` profile；
- CLI 与 `SimulationAudit` 输出信息 trace 和随机状态；
- 严格回归 manifest 与模块归属清单同步更新；
- `p3_narrative` 的配置测试改为在测试作用域注入并恢复占位环境变量，使清洁源码不依赖本地 `ai.local.json`。

既有 `framework` profile 保持信息层关闭。P7.0 的运行入口是 `information` profile。

## 5. 验收结果

### 5.1 P7.0 严格测试

`game/test/p7_information_subgoal.gd` 共 70 个断言，覆盖：

- blocker 到信息目标的确定性映射；
- 候选排序、目标身份、取消、尝试上限和冷却；
- 搜索位置、重复尝试、事件证据；
- 报告的边界、来源、时间、置信度和覆盖规则；
- UNKNOWN、STALE、REFUSE 与分享意愿；
- ToM 知情证据和可见性门；
- 父计划从 BLOCKED 变为 READY；
- 错误报告的亲眼推翻；
- 信息 RNG 与世界 RNG 隔离；
- information profile 的同输入确定性。

实际测试结果：`70 / 70 PASS`。

### 5.2 完整严格回归

最终命令：

```bash
python3 scripts/run-strict-regression.py \
  --godot /path/to/Godot_v4.7.2-stable_linux.x86_64 \
  --evidence .tmp/p7_strict_final_r3_20260911
```

结果：**PASS，36 组 Godot 测试 / 969 个断言，18 个 Python 测试，模块边界 gate 通过。** 引擎版本为 `4.7.2.stable.official.ed1daf0bf`。输入和输出源码指纹均为：

```text
6ef0863d2b2c84f3b4a49abb847649e3a1f44e35db4ad0109afadf36ea822fa0
```

`source_unchanged=true`。第一次清洁环境完整回归得到 968 / 969，失败项是 `p3a3_load_config_valid_when_set`。该旧测试依赖被 `.gitignore` 排除的本地 `game/config/ai.local.json`。随后把测试改为在作用域内设置占位环境配置并恢复原环境，定向 `p3_narrative` 得到 78 / 78，最终完整回归全部通过。修复没有添加真实密钥，也没有更改 LLM renderer 的运行逻辑。

### 5.3 1000 tick 重放

`framework` 与 `information` 都使用 seed 61003、1000 tick，并开启 `--verify-replay`。

| Profile | replay | events | execution | adoption | information | state |
|---|---|---|---|---|---|---|
| framework | true | `0a98e8d7fddda86a313eadfb6f94bed3e13fac01d32e08bbb80481bc89c7973d` | `65717b5eeb0fb2537aed3eff9d293dcedd38a56b3554bd09942914b2ef5212b6` | `85c587c4bea4a78a4849adac361b2329c3321919b99623bce7fef787e862a3b7` | `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945` | `73e4da19afd9cc56e7457da9c3e17fae3bae4c66507463d23b9ec0a6eff67022` |
| information | true | `1211518e45edd6f65619acf8c493fda8841d500ffa0185b6443bcfc2b14ea415` | `b08eda2186535e367f2fc2b530343410a89f059c73c69f1a7ba7ec68e3de6896` | `d6f26f30b03202f5b53e927f20a6cf9fbe871588c3bd66d7d80b36969de06089` | `e7858a30e200f3f82f86d544da26e6ba5ebba2e7b1569b75eb9080633a16a8e5` | `4a91cfa95d11c717257e23712918c7d2bea68eb0271960ab67ac5fb1ceb5b0f5` |

两组地图 hash 均为 `sha256:19005c0ae456db591658cd5eca05b45ea55ab349b6880ddf499a4837a7aecd43`。information 运行创建 6 个信息目标，解决 1 个，产生 2 次失败搜索和 1 次成功搜索；信息 trace 共 15 行。自然运行仍未产生询问。

### 5.4 framework 行为兼容

信息功能关闭时，修改前后的 seed 61003、1000 tick 事件流水、计划执行 trace、计划采纳 trace 与汇总逐项一致。对应数量分别是 1077 条事件、162 行执行 trace 和 1322 行采纳 trace。空间信念新增了报告元数据字段，因此跨版本完整 snapshot 与 state 指纹属于扩展后的 schema，单独记录，不用于声明逐字兼容。

### 5.5 Observer 启动检查

```bash
/path/to/Godot_v4.7.2-stable_linux.x86_64 \
  --headless --path game --quit-after 180 \
  res://scenes/observer/observer_main.tscn
```

结果为 exit 0，日志中没有 `ERROR`、`SCRIPT ERROR` 或测试失败。该检查只验证既有观察场景可以启动，本轮没有进行 UI 或美术改动。

## 6. 固定自然实验

实验脚本：`game/test/p7_information_pilot.gd`。两组均使用 P6.4 framework；treatment 只开启 `information_subgoals`。seed 为 61000 至 61009，每组 1000 tick，地图、角色、经济参数、资源布置和 timeout 相同。

| 指标 | 结果 |
|---|---:|
| 信息目标创建 | 47 |
| 信息目标解决 | 2 |
| 信息目标取消 | 38 |
| 搜索尝试 | 15 |
| 搜索找到来源 | 1 |
| 搜索未找到 | 14 |
| 询问尝试 | 0 |
| 分享 / 拒绝 / 过期 / 不知道 | 0 / 0 / 0 / 0 |
| 信息解决后父计划启动 | 1 |
| 出现行为分叉的 seed | 9 / 10 |
| baseline 完成计划 run | 35 |
| treatment 完成计划 run | 27 |
| 两组完整 ACQUIRE/CRAFT/MAIN | 0 / 0 |
| 第一 treatment 重放 | 一致 |
| 审计 violation | 0 |

完成 run 数下降不代表机制收益。信息行为占用了决策机会，并且目前大多数搜索未找到来源。实验支持“缺口已成为真实行为并能改变轨迹”，尚未支持“整体故事质量已经提高”。

自然询问为零，说明当前三角色场景中 `knows_source` 的目击证据、可见相遇和信息目标在同一时段重合得很少。询问完整路径已经通过受控场景验收，后续自然频率需要通过社会知识传播和材料请求链继续观察，不能通过无条件广播或扫描他人真值制造。

## 7. 已知限制

- 信息子目标只处理当前 Problem Ontology 支持的 HUNGER、THIRST、ISOLATION 计划 blocker。
- 一次目标只选择最高主观价值的缺口，尚未维护多目标队列。
- 报告可以继续作为行动依据，直到亲眼复核或规划上下文变化；长期置信度衰减尚未独立实现。
- 自然询问和完整制作链在固定实验中仍为零。
- P7.0 不处理物品请求、交换条件、债务或履约后果。
- 运行中 checkpoint 恢复和跨版本迁移仍属于 RUNTIME-R1。
- UI 与美术保持原样。

## 8. 下一阶段

P7.1 把 `MISSING_ITEM` 或已知来源但获取受限的材料缺口接入社会请求。请求目标来自角色自己的库存信念和关系证据。接受、拒绝与实际转移分别产生事件；只有物品转移证据可以推进父计划。

小说认知 N1 的前置条件已经部分满足。真实文本抽取计划在 P7.1 完成后启动，使案例可以覆盖搜索、询问、请求和协商，同时保持案例知识与角色本时间线记忆分离。

## 9. 设计考虑

P7.0 先解决计划成为 READY 之前的信息障碍，避免继续给前置动作叠加固定 bonus。信息进入世界的路径保持可追溯，角色可以相信错误消息，后续感知也能修正。

搜索、询问和原有行为共用决策竞争，信息目标没有强制执行权。新增行为放在独立 profile 中，便于对照 P6.4 基线。结构测试与自然频率分别报告，当前的零询问和零完整链继续作为下一阶段的真实输入。

# P6.4 + P6.N0 本地整合报告

整合日期：2026-09-10

本地项目：`D:\Project_AI\aiworld`

范围：P6.3B-4 因果步骤价值、P6.4 Framework/Plan Adoption、P6.N0 Cognitive Cases，以及本地兼容修复

明确排除：P7 新功能、UI 重做、美术生产、资源数量/位置优化

## 1. 基线与整合策略

- 整合前分支：`main`
- 整合前 HEAD：`498f55a07fc693f39caced22dbe7196c7e64d3fa`
- 整合前工作区：干净
- 交付方目标标识：`4b4a0036dd22b7ab5b61f1bbcaeb3fea14aa7b41`
- 交付方声明基线：`b86a1a482f118617b29381c7ba9c639cfaf9b389`
- 本地 Git 历史与交付方历史不同，因此交付方提交号仅用于追溯，没有在本地执行 reset、merge 或强制覆盖。

交付包 SHA-256 与两份 manifest 全部一致。首先执行了
`git apply --check AIWorld_P6_4_framework_N0.patch`；检查因本地路线文档、
`island_simulation.gd`、`plan_execution_tracker.gd` 和严格回归入口已分叉而失败。
因此正式选择 **完整源码快照逐文件整合**，补丁只用于识别发布改动和对照上下文，未实际应用，避免重复导入。

## 2. 实际整合内容

从目标源码快照导入或合并了 63 个目标文件：交付补丁列出的 60 个文件，以及因交付方输入基线不同、未出现在补丁增量中的 3 个必需文件：

- `game/src/simulation/decision/plan_step_value_model.gd`
- `game/test/plan_step_value.gd`
- `game/test/p6_3b_causal_value_pilot.gd`

主要能力包括：

- P6.3B-4：根问题因果价值向 ACQUIRE/CRAFT 等前置步骤传播，开关独立；
- P6.4：主观计划采纳、承诺重估、角色独立 adoption RNG 与只读 trace；
- framework/legacy/execution/causal 四档模拟配置；
- 无界面 1000 tick 运行、审计指纹和同输入重放入口；
- P6.N0 认知案例 schema、编译器、只读案例库和原创工程夹具；
- 35 套件统一严格回归清单、Python 案例测试与发布验证资料；
- Observer 仅增加模拟 profile 装配，没有重做 UI 或美术。

本地已有 P6.3B-2 资源目标重验和 P6.3B-3“按真实决策机会计数”的生命周期修复均被保留。源码快照中的关键文件本身已经包含这些语义；整合后相关旧测试继续通过。

## 3. 冲突与兼容性处理

### 3.1 补丁基线冲突

没有强行使用 `git apply --reject` 或覆盖本地目录。改用目标源码快照后，逐文件检查关键差异；`island_simulation.gd` 和 `plan_execution_tracker.gd` 的交付变化是在本地 P6.3B-3 语义之上增加 adoption/valuation，而不是回退本地修复。

### 3.2 交付方基线文件缺口

第一次完整回归发现 `res://test/plan_step_value.gd` 不存在。该文件及对应模型、pilot 在交付方输入基线中，所以不在增量补丁正文中。通过比较完整快照的 517 个文件，定位到仅有上述 3 个源码文件缺失并补齐；没有复制其余未变文件。

### 3.3 Windows console 换行

便携 Python runner 在 Windows 捕获 Godot console 输出时收到 CRCRLF，导致测试实际 exit 0 且日志包含 `SUMMARY`，但锚定正则读不到断言数。`scripts/runtime_tools.py` 增加统一输出解码和换行规范化；短探针随后正确识别 `199/0`。该修复不修改模拟逻辑、测试条件或断言数量。

### 3.4 Observer 启动路径

首次图形 smoke 把项目目录重复写入场景参数，Godot 尝试加载不存在的
`res://game/scenes/observer/observer_main.tscn`，因此失败。修正为项目内路径
`res://scenes/observer/observer_main.tscn` 后 exit 0 且无引擎错误。失败与成功日志均保留，
没有通过忽略错误来宣称通过。

## 4. 环境

| 项目 | 本地实测 |
|---|---|
| OS | Microsoft Windows NT 10.0.26100.0 |
| Git | 本地仓库命令可用 |
| Godot | 4.7.2.stable.official.ed1daf0bf |
| Python | 3.12.14（Codex bundled runtime） |
| Node.js | v24.19.0 |

系统 `python` 命令当前命中 Windows 商店占位入口，`py -3` 也未返回可用解释器；验收使用明确记录的 bundled Python 绝对路径。项目脚本仍保持 Python 3.10+ 的跨平台约束。

## 5. 验收结果

### 5.1 严格回归

最终命令：

```powershell
C:\Users\12072\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe `
  scripts/run-strict-regression.py `
  --godot tools/Godot_v4.7.2-stable_win64_console.exe `
  --evidence .tmp/p6_4_local_strict_r2_20260910
```

最终结果：**PASS — 35 Godot suites / 899 assertions；18 Python tests；模块边界通过；source_unchanged=true**。

- source SHA-256 before/after：`227f74e9f2946f93e1034bf44e9a4b8521b24f82dc9c690ac044dc31f786902`
- P6.3B execution：28/28
- P6.3B-4 plan step value：18/18
- P6.4 plan adoption：36/36
- framework runtime：17/17
- P6.N0 cognitive cases：21/21

此前实际运行记录：

1. `.tmp/p6_4_local_strict_20260910`：发现 Windows 换行解析兼容问题后主动中止；已执行套件的 Godot 进程为 exit 0，但 runner 无法读取断言数，后续套件未执行。
2. `.tmp/p6_4_local_strict_r1_20260910`：完整执行；34/35 Godot 套件通过，`plan_step_value` 因文件缺失失败，结果 881/899；Python 18/18、模块边界通过。
3. `.tmp/p6_4_local_strict_r2_20260910`：补齐完整源码基线并修复 runner 后，全部通过。

### 5.2 1000 tick 同输入重放

```powershell
C:\Users\12072\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe `
  scripts/run-simulation.py `
  --godot tools/Godot_v4.7.2-stable_win64_console.exe `
  --ticks 1000 --seed 61000 --profile framework --verify-replay `
  --out .tmp/p6_4_local_world_61000.json
```

结果：**exit 0，tick=1000，actors=3，replay_verified=true**。

| 指纹 | SHA-256 |
|---|---|
| events | `b144f8ecb12d311dd882df0fba58acc731f03d3eb801500ce05d0434586a9c25` |
| execution | `ecfc7c1463dede765388881316e0e98c0ed2e2f30396f6c4b4ed9e5dcb8d625e` |
| adoption | `68cf66dda38f175979966f9a08174f13ccda31357d8f931fc8fd8a0e96bf4d49` |
| state | `b9c83eb69e6b8215c93b65229cdb7b12755e58c5539e34a23c20c5c9c4587542` |

### 5.3 既有 Observer 兼容检查

- 首次错误路径：exit 1，场景未加载；归类为验收命令错误。
- 修正为 `res://scenes/observer/observer_main.tscn`：exit 0，无 `ERROR`/`SCRIPT ERROR`。
- 本轮只检查启动兼容性，没有进行 UI/美术验收或修改。

## 6. 未解决问题与未执行项

- 固定自然实验中完整 `ACQUIRE → CRAFT → MAIN` 链仍为零，这是交付方已披露的产品缺口；本轮没有通过调整浆果、seed、timeout 或固定奖励掩盖。
- 运行中途 checkpoint 保存/恢复和跨版本迁移仍未实现。
- N0 是带原文证据的工程夹具与只读接口，不等同于自动阅读整本小说或训练模型。
- 未执行 P7 信息搜索、材料请求、承诺后果等新功能。
- 未重做 UI 和美术；只执行 Observer 启动 smoke。

## 7. 本轮证据与导出

本地证据源：

- `.tmp/p6_4_local_strict_r2_20260910/`
- `.tmp/p6_4_local_world_61000.json`
- `.tmp/run-20260910T101728740354Z/`

对外交付目录使用 `D:\Project_AI\aiworld-deliveries\P6_4_LOCAL_INTEGRATION_20260910\`，其中包含整合后源码 ZIP、验收日志 ZIP 和导出清单。源码 ZIP 排除 `.git`、`.tmp`、Godot 缓存、引擎、依赖缓存及本地敏感配置。

解压审阅目录 `.tmp/p6_4_delivery_review/` 与源码对照目录
`.tmp/p6_4_source_reference/` 在导出完成后曾按绝对路径校验并尝试精确删除，但宿主执行策略阻止了递归删除命令。两者仍位于 Git 忽略的 `.tmp` 内，不进入源码包；未改用跨 shell 或更危险的删除手段绕过策略。

## 8. 当前 Git 状态

整合报告生成时 HEAD 仍为整合前的 `498f55a07fc693f39caced22dbe7196c7e64d3fa`；本轮改动保留为未提交的整合候选，便于用户或下一轮开发在复核后建立 checkpoint。没有覆盖或丢弃整合前本地工作。

# 运行与验收

更新：2026-09-10。验证环境：用户提供的 Linux Godot，版本输出 `4.7.2.stable.official.ed1daf0bf`。所有命令从项目根目录执行。

## 1. 无界面运行

将引擎解压为可执行文件，路径可以位于工程之外。Linux 示例：

```bash
chmod +x /path/to/Godot_v4.7.2-stable_linux.x86_64
python3 scripts/run-simulation.py \
  --godot /path/to/Godot_v4.7.2-stable_linux.x86_64 \
  --ticks 1000 --seed 61000 --profile framework \
  --verify-replay --out .tmp/world-61000.json
```

Windows PowerShell 示例，沿用原项目引擎：

```powershell
python scripts/run-simulation.py --godot tools/Godot_v4.7.2-stable_win64_console.exe --ticks 1000 --seed 61000 --profile framework --verify-replay --out .tmp/world-61000.json
```

这里的 Windows 命令按跨平台脚本提供。本轮实际执行环境为 Linux，Windows 尚未在本轮重跑。

`--out` 指向新文件，已有文件会被拒绝覆盖。`--verify-replay` 会从同一初始条件重算第二遍，比较世界与角色的诊断指纹。运行中途恢复存档属于后续里程碑，此参数执行的是从初始输入重放。

运行依赖 Python 3.10+ 与 Godot。Python 入口使用标准库。首次运行自动执行 headless editor import；同一份源码已经导入时，可使用 `--skip-import`。也可以设置环境变量 `GODOT_BIN`，随后省略 `--godot`。

输出 JSON 包含：

| 字段 | 用途 |
|---|---|
| `events` | 实际事件流水，保留事件序号和行动结果 |
| `plan_adoption_trace` | 计划估值、采纳/暂缓/保留、概率和理由 |
| `plan_execution_trace` | 计划步骤、实际尝试、完成证据与中断原因 |
| `final_snapshot` | 观察用最终快照，部分对象经过摘要处理 |
| `fingerprint` | 事件、执行、采纳和运行时对象状态的校验值 |
| `replay_verified` | 开启重放时的比较结果；未开启时为 null |

地形继续使用 `game/data/demo_world/world_spec.json` 的固定世界输入。命令中的 `--seed` 控制本场景资源布置和角色随机流，独立于地形种子。当前入口加载已有的三角色荒岛场景，并未接入任意小说文本直接生成整个场景的功能。

## 2. 完整严格回归

```bash
python3 scripts/run-strict-regression.py \
  --godot /path/to/Godot_v4.7.2-stable_linux.x86_64 \
  --evidence .tmp/strict-local-001
```

证据目录需要尚未存在。入口读取 `scripts/strict_suites.json`，统一执行 35 组 Godot 测试，再运行模块边界检查和 18 个 Python 小说案例导入测试。Godot 断言目标为 899 个。每组退出码、实际断言数、异常和源码指纹都写入 `summary.json`，原始日志保留在同目录。

Node.js 用于项目既有的模块边界检查。该检查只覆盖字面量 `load/preload`，动态调用和全局类依赖还需要人工检查。测试期间修改运行源码或测试输入会使最终 `source_unchanged` 为 false。

保留的 PowerShell 入口转调同一份 Python runner：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/run-strict-regression.ps1 -GodotPath tools/Godot_v4.7.2-stable_win64_console.exe -EvidenceDirectory .tmp/strict-local-001
```

## 3. 运行配置

`game/config/simulation_profiles.json` 提供四档设置：

| 配置 | 计划执行 | 前置步骤价值 | 主观计划采纳 |
|---|---|---|---|
| `legacy` | 关 | 关 | 关 |
| `execution` | 开 | 关 | 关 |
| `causal` | 开 | 开 | 关 |
| `framework` | 开 | 开 | 开 |

Observer 装配入口读取文件中的 `default_profile`，默认 `framework`。底层 `IslandSimulation` 的默认值仍保持旧模式，便于旧回归与显式开关比较。已有观察界面启动时也会使用相同配置；本轮只修改这一装配接线，未重做界面或美术。

需要从命令行临时选择观察模式的配置时：

```bash
/path/to/godot --path game -- --simulation-profile=legacy
```

## 4. 自然实验与诊断

先完成 Godot import，再执行：

```bash
/path/to/godot --headless --path game --script res://test/p6_4_adoption_pilot.gd -- --out=/absolute/new_adoption_pilot.json
/path/to/godot --headless --path game --script res://test/agency_funnel_probe.gd -- --out=/absolute/new_funnel.json
```

自然实验固定种子 61000 至 61009，每组 1000 tick。两组使用相同资源、场景、经济配置和 timeout，差异限定为计划采纳开关。诊断脚本仅观察提案、认知缺口和采纳记录；统计中的 repeated opportunities 表示重复决策机会，不能读成独立故事数量。

目前的完整 `ACQUIRE → CRAFT → MAIN` 自然完成次数仍为零。规则测试通过只说明接口和约束符合已写断言，产品层的自主委托故事仍需 P7 验收。

## 5. 小说案例导入

仓库内附一段原创工程样本，供格式验证使用：

```bash
python3 narrative-learning/compile_cases.py \
  --input lore/cognition_fixture.cases.json \
  --source-root lore \
  --out .tmp/cognitive-cases.json
```

该命令验证预先标注的案例，并编译只读案例包。它不会自动阅读整本小说完成抽取，也不执行模型训练。已审核的真实小说案例沿用同一接口，要求见 `NOVEL_COGNITION.md`。

## 6. 当前运行边界

现有程序可以在进程内持续推进并输出完整事件记录。长期存档恢复、跨版本迁移和事件归档压缩仍需要专门实现。当前默认案例包为工程测试样本，运行配置不会自动将它注入角色决策。LLM 的后续接入必须经过结构化候选与合法性检查，世界状态继续由规则系统裁决。

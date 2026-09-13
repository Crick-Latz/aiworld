# 运行与验收

更新：2026-09-11。P7.0 验证环境使用 Linux Godot `4.7.2.stable.official.ed1daf0bf`。所有命令从项目根目录执行。

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
| `information_subgoal_trace` | 信息目标、搜索/询问尝试、解决或取消原因与证据引用 |
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

证据目录需要尚未存在。入口读取 `scripts/strict_suites.json`，统一执行 36 组 Godot 测试，再运行模块边界检查和 18 个 Python 小说案例导入测试。Godot 断言目标为 969 个。每组退出码、实际断言数、异常和源码指纹都写入 `summary.json`，原始日志保留在同目录。

P7.0 的 Linux 清洁环境实测结果为 **36 组 / 969 个 Godot 断言、18 个 Python 测试全部通过**，模块边界 gate 通过，`source_unchanged=true`。对应源码指纹与详细记录见 `game/docs/validation/p7_0_information_subgoal_for_gpt.md`。

Node.js 用于项目既有的模块边界检查。该检查只覆盖字面量 `load/preload`，动态调用和全局类依赖还需要人工检查。测试期间修改运行源码或测试输入会使最终 `source_unchanged` 为 false。

保留的 PowerShell 入口转调同一份 Python runner：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/run-strict-regression.ps1 -GodotPath tools/Godot_v4.7.2-stable_win64_console.exe -EvidenceDirectory .tmp/strict-local-001
```

## 3. 运行配置

`game/config/simulation_profiles.json` 提供五档设置：

| 配置 | 计划执行 | 前置步骤价值 | 主观计划采纳 | 信息子目标 |
|---|---|---|---|---|
| `legacy` | 关 | 关 | 关 | 关 |
| `execution` | 开 | 关 | 关 | 关 |
| `causal` | 开 | 开 | 关 | 关 |
| `framework` | 开 | 开 | 开 | 关 |
| `information` | 开 | 开 | 开 | 开 |

Observer 继续读取文件中的 `default_profile`，默认 `framework`。P7.0 通过 `information` profile 单独启用，使既有 framework 轨迹可以直接做兼容对照。底层 `IslandSimulation` 默认仍关闭新增层。

运行信息层：

```bash
python3 scripts/run-simulation.py \
  --godot /path/to/Godot_v4.7.2-stable_linux.x86_64 \
  --ticks 1000 --seed 61003 --profile information \
  --verify-replay --out .tmp/information-61003.json
```

需要从命令行选择观察模式时：

```bash
/path/to/godot --path game -- --simulation-profile=information
```

## 4. 自然实验与诊断

P6.4 计划采纳实验与诊断入口继续保留。P7.0 使用配对实验，只切换 `information_subgoals`：

```bash
/path/to/godot --headless --path game \
  --script res://test/p7_information_pilot.gd -- \
  --seeds=10 --ticks=1000 \
  --out=res://docs/validation/data/p7_0_information_pilot.json
```

输出文件必须尚未存在。默认 seed 为 61000 至 61009。实验保持地图、角色、资源、经济参数和 timeout 一致，记录信息目标、搜索、询问、消息结果、父计划恢复、行为分叉和完整计划链。自然频率属于观察指标，测试不会要求特定故事数量。

当前固定实验创建 47 个信息目标，解决 2 个，完成 15 次搜索，其中 1 次找到来源；1 个父计划在信息解决后启动。自然样本中的询问为零，完整 `ACQUIRE → CRAFT → MAIN` 链为零。受控严格测试覆盖询问、分享、拒绝、过期报告和错误报告复核。

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

## 7. UI 观察模式（UI-R1 2D 像素原型）

观察模式默认进入 2D 俯视像素小地图原型（48×36 六分区舞台；内部渲染 480×270、16×16
图块、整数倍放大，窗口默认 1920×1080）。地形含 Kenney Tiny Farm CC0 混合层。
`AIW_UI_MAP=full` 可让观察模式回到 64×64 全图。

```bash
# 正式观察（island 认知岛模拟 + 2D 像素世界 + Inspector/时间线）
tools/Godot_v4.7.2-stable_win64_console.exe --path game

# 离线 HUD 布局预览（无模拟依赖；fixture 见 scenes/ui/ui_preview.gd）
tools/Godot_v4.7.2-stable_win64_console.exe --path game res://scenes/ui/ui_preview.tscn
#   AIW_PREVIEW_FIXTURE=NPC_SELECTED 等可选夹具；AIW_PREVIEW_TAB=memory 可预选页

# 截图工具（窗口模式）
tools/Godot_v4.7.2-stable_win64_console.exe --path game res://scenes/observer/ui_capture.tscn --   --mode=observer --select=npc_weila --tab=memory --out=D:/abs/shot.png --frames=240

# 旧 3D 演示模式（wander/story）仍可用：
AIW_MODE=wander tools/Godot_v4.7.2-stable_win64_console.exe --path game
```

ViewModel 契约与字段清单见 `docs/ui/OBSERVER_VIEW_MODEL.md`；像素资产（全部自制占位，
可再生成）见 `docs/ui/ASSET_MANIFEST.md`；架构与已知限制见 `docs/ui/ui-architecture.md`。

## 8. GitHub 自动验收

`.github/workflows/framework-ci.yml` 在面向 `main` 的 Pull Request 和 `main` push 上运行。工作流下载 checksum 固定的 Godot 4.7.2 Linux 引擎，执行完整严格回归、framework 1000 tick 重放及 information 1000 tick 重放，并保留 14 天证据 artifact。

本地结果与 GitHub Actions 分别记录。PR 合并前应确认目标 commit 的 CI 结论。

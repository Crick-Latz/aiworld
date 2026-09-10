# AIWorld

持续运行的因果世界原型。Godot 负责世界状态与行动结算，角色依据自己的信息形成计划。当前优先完成模拟框架，UI 与美术保持原样。

当前交付为 **P6.4 Framework + P6.N0 Cognitive Cases**。新的无界面入口可以运行现有荒岛场景，并输出事件、计划采纳与执行证据。真实小说自动抽取、P7 社会子目标、完整运行中存档恢复仍有后续工作。

## 从这里开始

- [运行与验收](docs/RUNNING.md)：Linux / Windows 命令、运行配置、输出说明。
- [项目路线图](docs/ROADMAP.md)：阶段状态、后续顺序与 UI 开始前的验收条件。
- [小说认知案例接口](docs/NOVEL_COGNITION.md)：证据格式、审核要求、导入与调用边界。
- [本轮验证报告](game/docs/validation/p6_4_framework_for_gpt.md)：完整回归、自然实验和限制。

源代码包保留现有工程结构。引擎沿用你已有的版本，放到 `tools/` 或通过 `--godot` 指定。首次启动会导入 Godot 工程缓存。运行新的 Python 脚本需要 Python 3.10+，模块边界检查需要 Node.js；这条无界面运行路径无需安装 npm 依赖，也无需 LLM 凭据。

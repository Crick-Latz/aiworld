# GitHub 首次导入报告

日期：2026-09-10。

- 仓库：`Crick-Latz/aiworld`，可见性为 private。
- 正式分支：`main`。
- 导入后的基线：`dff3b5de1483f9b863dc698c7ab48d2488740923`。
- GitHub 原始占位 `main`：`92471dd45f49dd1b6d059fc6ff25128b7993ad6f`。
- 原始占位版本备份：`archive/github-initial-main`。
- 运输分支：`bootstrap/p6-4-local-integrated`。
- 运输格式：经 `git bundle verify` 校验的 Git bundle。
- 自动导入工作流：`Import AIWorld Git bundle`，run `34475952746`，结论 success。

导入保留了本地项目历史和 P6.4 + P6.N0 checkpoint。缓存、依赖副本、引擎、本地 AI 配置和凭据未进入正式源码树。关键路径 `game/project.godot`、`docs/handoff/P6_4_LOCAL_INTEGRATION_REPORT.md` 与 `docs/handoff/DELIVERY_PROTOCOL.md` 已在远程 `main` 核对。

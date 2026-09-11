# P7.0 GitHub 交接

日期：2026-09-11。

## 基线与分支

- 仓库：`Crick-Latz/aiworld`
- 输入基线：`dff3b5de1483f9b863dc698c7ab48d2488740923`
- 工作分支：`work/p7-0-information-subgoal`
- 目标分支：`main`

## 本轮范围

本轮实现 `UNKNOWN_SOURCE` 信息子目标、主观搜索、基于 ToM 证据的询问、回答者主观报告、拒绝和过期结果、报告复核、父计划重验、独立信息随机流及诊断输出。

本轮保持 UI、美术、资源数量、固定 seed、timeout 和原有经济参数不变。P7.1 材料请求、P7.2 履约后果、N1 真实小说抽取与 RUNTIME-R1 存档恢复未进入本分支。

## 验收

- P7.0 定向测试：70 / 70。
- 完整严格回归：36 组 Godot 测试，969 / 969 个断言。
- Python 认知案例测试：18 / 18。
- 模块边界 gate：通过。
- framework seed 61003、1000 tick：同输入重放通过，且信息层关闭前后的事件、执行 trace、采纳 trace 与汇总一致。
- information seed 61003、1000 tick：同输入重放通过；创建 6 个信息目标，解决 1 个。
- Observer headless 180 帧启动检查：exit 0。
- 固定 10 seed 配对自然实验：创建 47 个信息目标，解决 2 个；自然询问和完整多阶段链仍为零。

清洁环境第一次完整回归暴露旧 `p3_narrative` 测试依赖本地 AI 配置的问题。测试现已使用作用域内占位环境变量，并在结束时恢复原值。最终结果以 `game/docs/validation/p7_0_information_subgoal_for_gpt.md`、Pull Request 目标 commit 与 GitHub Actions 为准。

## 整合方式

通过 Pull Request 审查并合并本分支。源码 ZIP 与补丁不作为常规整合路径。Windows 本地出现差异时，从 PR head 拉取后运行 `docs/RUNNING.md` 中的严格回归命令，并把本机日志单独回传。

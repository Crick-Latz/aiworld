# AIWorld AI 开发交接说明

更新时间：2026-09-11

> 本文件是给接手 AIWorld 的其他大模型、Codex、IDE Agent 或人工开发者使用的当前状态入口。开始工作前必须先读取 GitHub `main` 最新提交，再阅读本文件、`docs/ROADMAP.md`、相关阶段 handoff 与验证文档。若本文中的 commit 与 GitHub `main` 不一致，以 GitHub 最新 `main` 为准，并先检查新提交内容。

## 1. 项目目标

AIWorld 要实现一个由 AI 辅助生成、由规则模拟持续运行、能够自主产生故事的世界。用户输入世界观或故事背景后，系统生成地图、角色与势力。角色拥有自己的性格、目标、关系、记忆和有限认知，并根据世界变化自主行动。

第一版使用 Godot，优先 2.5D 上帝视角观察。玩家暂时不直接控制角色。当前开发重点是模拟框架和因果闭环，UI、美术与大规模内容扩充后置。

核心产品原则：

1. 随机性必须受因果、状态和角色认知约束。
2. 角色只能依据自己知道或相信的信息决策，不能读取全局真相作为隐形攻略。
3. 对话、计划或 LLM 输出不能直接修改世界事实；库存、资源、死亡、移动等变化必须经过规则执行与事件证据。
4. 后续发展必须记得已经发生的改变，并允许旧计划因前提失效而结束或重构。
5. 观察者应能追溯“发生了什么、角色当时知道什么、为什么这样行动、结果改变了什么”。
6. LLM 适合世界输入编译、离线案例抽取、候选建议和语言表达；世界事实、合法性与结算由模拟器负责。

目标不是 AI 续写小说，而是让叙事从持续运行的世界状态中生长。

## 2. 当前正式 GitHub 基线

仓库：`Crick-Latz/aiworld`

默认分支：`main`

本文件创建前已确认的正式基线：

```text
9e7abda99f76878c010f234e079e19bd6d1dd6b7
feat(p7.1): establish causal material request foundation (#5)
```

该提交已经通过正式 GitHub Actions `AIWorld framework verification`：

- full strict regression：通过
- stable `framework` deterministic replay：通过
- experimental `information` deterministic replay：通过
- verification evidence artifact：上传成功

对应成功 run：`34579203628`。

注意：创建本 handoff 文件会在 `main` 上产生一个仅文档变更的新 commit，因此接手者看到的 `main` SHA 预计会高于 `9e7abda...`。先确认新 commit 是否只有交接文档，再继续开发。

## 3. 当前已经完成的能力

### 世界与运行框架

- 世界文本编译和结构化世界规格
- 确定性随机地图
- 基础移动、观察和无渲染运行入口
- 统一 simulation profile、CLI、诊断指纹和可重放运行

### P1-P2：角色与社会基础

已有性格、需求、意图、主观解释、Theory of Mind、关系、请求、承诺和制度基础。接手时应复用这些模块，避免建立第二套平行社会系统。

### P3-P4：叙事呈现

已有 Narrative IR、事件解释和故事线程。它们属于事件发生后的解释/呈现层，不拥有世界结算权。

### P5：有限认知

已有主观空间认知、资源信念、信息失效和重访修正。角色决策必须继续尊重有限认知边界。

### P6：问题、规划与执行

已有知识包、问题激活、手段规划、合法动作桥、物品/配方、类型化步骤、执行凭据、前提重查、计划采纳/暂缓、承诺保留和重考虑。

### P6.N0：小说认知旁路基础

已有案例证据校验和只读检索。N1 真实文本导入计划位于 P7.1 闭环之后、UI 美术之前。

### P7.0：信息缺口成为行动

已实现 `UNKNOWN_SOURCE(item)` → 信息子目标：

```text
角色缺少某资源来源知识
→ FIND_SOURCE
→ 基于自己的空间信念搜索，或基于 ToM 证据询问可见角色
→ 获得带来源/时间/置信度的观察或消息
→ 更新主观认知
→ 父计划重新验证
```

重要约束：信息目标解决不转移物品，不伪造计划完成；亲眼观察可以推翻过期或错误报告；信息交换使用独立 RNG namespace。

P7.0 自然实验仍暴露两个产品缺口：自然询问出现率低，完整 `ACQUIRE → CRAFT → MAIN` 链仍不足。这些属于后续机制输入，不应通过改 seed、加资源、放宽 timeout 或固定奖励掩盖。

### P7.1A：材料请求基础

正式 `main` 已加入：

- `MaterialRequestContract`
- `MaterialRequestTracker`
- `MaterialRequestPolicy`
- `MaterialRequestResponsePolicy`
- `MaterialTransferService`
- `MaterialRequestCoordinator`
- 对应 lifecycle / hardening 测试

能力边界：

```text
材料缺口
→ 根据请求者的主观 holder belief 选择对象
→ 对方根据自己的库存、需求、关系、风险、承诺等接受 / 拒绝 / counter
→ 接受本身不完成材料步骤
→ 实际库存转移产生 ITEM_TRANSFER_COMPLETED 证据
→ 匹配请求才允许 resolved
→ 生成一次性 parent-plan revalidation
```

候选对象不得来自全局真实库存扫描。库存变化可以使先前承诺在执行时失败。策略评估不能偷偷修改库存。

## 4. 当前下一项开发任务：P7.1B Runtime Wiring

下一位开发者应从最新 `main` 创建新的工作分支，例如：

```text
work/p7-1-runtime-wiring
```

不要继续使用旧的 P7.0/P7.1 临时恢复分支。

目标是把 P7.1A 的材料请求领域模块接入真实 IslandSimulation / 角色计划执行循环，使请求由真实材料 blocker 自主产生，而非仅在受控单元测试中调用。

最小因果链：

```text
A 的已采纳父计划需要材料
→ 当前真实/主观前提判断形成材料 blocker
→ A 从自己的认知中选择可能持有材料且当前可交互的 B
→ A 发起 material request
→ B 用自己的状态决定接受、拒绝或 counter
→ 若达成条件，执行时重新检查真实库存和合法性
→ MaterialTransferService 实际转移物品并写事件
→ request 只根据匹配 transfer evidence resolved
→ 消耗一次 parent revalidation token
→ A 重新构建/验证父计划并继续
```

必须覆盖失败路径：

- 没有主观候选对象
- 候选不可见/信息过期
- B 拒绝
- B counter，A 接受或放弃
- B 答应后库存发生变化，转移失败
- 请求过期
- 重复消息或重复 transfer evidence
- unrelated transfer 不得推进请求
- 父计划已失效时不得强行恢复

### P7.1B 验收要求

1. 新增定向 Godot 测试，覆盖完整 runtime chain 和上述关键失败路径。
2. `framework` profile 行为保持兼容。
3. `information` profile 的 P7.0 能力保持兼容。
4. 使用固定 seed 做自然运行实验，记录请求创建、接受、拒绝、counter、真实转移、父计划恢复及最终制作链完成情况。
5. 自然实验结果如实记录。禁止为了“出现故事”修改固定 seed、增加资源、放宽 timeout 或硬塞固定 utility bonus。
6. 完整 strict regression 必须通过。
7. 两个既有 deterministic replay 必须继续通过。
8. 代码、实验数据和验证说明一起提交。

## 5. P7.1B 之后的计划

### P7.2：承诺后果与自主委托故事

让协商形成有条件承诺，成功、违约和误解进入关系与记忆，并改变下一次合作概率。

最小产品目标是一条 3-6 角色自主推动的因果链：

```text
缺口出现
→ 寻求帮助
→ 协商改变条件
→ 资源真实转移
→ 父计划执行
→ 履约或违约
→ 关系与后续行为改变
```

“委托”应是观察层对世界矛盾和角色行动的命名，不应由固定 QuestGenerator 凭空生成。

### N1：小说认知真实案例导入

在 P7.1 材料请求闭环完成后启动。使用合法获得的小说/文本做离线抽取、人工审核和反事实评估，先 SHADOW 检索。案例只能作为认知/策略参考，不能把原剧情或叙述者全知信息直接写成当前 NPC 的事实记忆。

### RUNTIME-R1：持续运行可靠性

补齐 IslandSimulation checkpoint / restore，保存随机流、行动进度、计划承诺和认知对象，并验证恢复后与不中断运行一致。随后处理事件归档、记忆压缩、版本兼容和长时间运行。

### UI 与美术

完成 P7 核心因果链和 RUNTIME-R1 后启动。首轮 UI 重点展示因果和认知：发生了什么、角色知道什么、为什么选择、后果怎样改变关系。

## 6. GitHub / CI 规则，必须遵守

历史上曾出现大量 Actions 红叉，主要原因是开发过程中创建了多套一次性 `finalize`、`recover`、`auto-merge` 工作流，并由 workflow 再提交触发其他 workflow。

已确认的典型旧错误是 `.github/workflows/p7-finalize.yml` 的 YAML `if:` 条件中包含 `: `，导致 workflow 在解析阶段失败。旧失败 run 示例：`34571052110`。

当前 `main` 的 `.github/workflows/` 应只保留：

```text
framework-ci.yml
```

后续规则：

1. 始终从最新 `main` 创建新功能分支。
2. 不创建一次性自动合并、payload 恢复、finalizer 或自修改仓库的 workflow。
3. 不根据 commit message 建立复杂的自动发布链。
4. GitHub Actions 只负责验证和保存证据。
5. 功能代码通过正常 branch → commit → PR → existing CI → merge 流程进入 `main`。
6. 历史红叉无需清除；判断健康状态看最新 `main` 的正式 `framework-ci.yml`。
7. Node.js 20 deprecation 等第三方 Action 黄色警告与当前功能验证分开处理，不因警告改变模拟逻辑。

## 7. 开发纪律

### 因果与认知

- authoritative world state 与 actor belief 分离。
- NPC 不能读取其未观察、未获知的世界事实。
- 消息必须保留来源、时间和置信度。
- 世界变化必须产生可引用事件。
- 父计划恢复必须重新验证当前前提。

### 随机性

- 相同 seed + 相同输入应可重放。
- 新机制尽量使用独立 RNG namespace，避免无关系统改变随机序列。
- 随机用于不确定决策和世界变化，不能替代因果条件。

### LLM 边界

- LLM 输出视为 proposal / interpretation / language realization。
- LLM 不直接写 authoritative inventory、位置、死亡、关系结果或任务完成。
- LLM 建议进入世界前必须经过 schema、规则合法性和当前状态验证。

### 测试

每个阶段至少需要：

- 定向单元/集成测试
- strict regression
- deterministic replay
- 固定 seed 产品实验
- 验证文档

“测试通过”和“自然故事频率提高”分别记账。禁止把产品实验结果伪装成单元正确性，也禁止为了指标通过修改实验条件。

## 8. 推荐先读文件

按顺序：

1. `docs/handoff/AI_HANDOFF_CURRENT.md`
2. `docs/ROADMAP.md`
3. `docs/NOVEL_COGNITION.md`
4. `docs/handoff/P6_4_LOCAL_INTEGRATION_REPORT.md`
5. `game/docs/validation/p6_4_framework_for_gpt.md`
6. `game/docs/validation/p7_0_information_subgoal_for_gpt.md`
7. P7.1 相关 handoff / validation 文件
8. `game/src/simulation/information/`
9. `game/src/simulation/material_request/`
10. IslandSimulation / plan execution / inventory / social system 相关实现
11. `scripts/run-strict-regression.py`
12. `scripts/run-simulation.py`
13. `.github/workflows/framework-ci.yml`

读取实际源码后再决定修改点，不要仅依据 handoff 猜测接口。

## 9. 接手模型开始工作时的标准动作

```text
1. 获取 GitHub main 最新 SHA
2. 检查最新 main 的 framework CI 是否绿色
3. 阅读本 handoff 和 ROADMAP
4. 阅读当前任务相关源码与测试
5. 创建新的 work/... 分支
6. 实现一个边界清楚的阶段
7. 运行定向测试 + strict regression + replay + 固定 seed 实验
8. 记录真实结果与已知缺口
9. 创建 PR
10. CI 绿色后再合并
```

遇到失败时先定位失败属于：YAML/CI 基础设施、测试环境、代码正确性、确定性、还是产品实验结果。不要通过增加新的 workflow 来掩盖旧 workflow 的问题。

## 10. 当前禁止事项

- 暂不进入 UI / 美术。
- 暂不扩 NPC 数量来制造故事密度。
- 暂不做大规模三国势力模拟。
- 暂不让 LLM 接管世界事实结算。
- 暂不通过改 seed、资源数量、timeout、固定奖励美化自然实验。
- 暂不建立第二套请求/关系/记忆系统。
- 暂不重新引入一次性 GitHub 自动合并/恢复工作流。

## 11. 交接结论

当前工程已经从“角色知道缺什么但无法行动”推进到：

```text
认知缺口可以触发信息行动
+
材料缺口已经拥有请求、协商、真实转移和父计划重验证的领域基础
```

下一步的价值集中在 **P7.1B runtime wiring**：让这些能力在持续运行的世界中由真实 blocker 自主触发，并观察它们能否自然产生合作、拒绝、counter 和计划恢复。完成这一步后，再推进 P7.2 的承诺后果与自主委托故事。

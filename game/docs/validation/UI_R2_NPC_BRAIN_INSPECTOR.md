# UI-R2 NPC 大脑观察器 —— 本地验证记录

## R1.2 Final Time-Semantics Closeout（2026-09-16，GPT R1.1 复审返修补轮）

R1.1 复审判 UI_R2_FINAL_SEMANTIC_EDGE_CASE_NEEDS_FIX（三主 blocker 关闭），一个边界修复：

- **无 live run 时的当前 live 信息目标**：原实现落入 section=snapshot（HUD 显示在
  「上次决策快照」下并与旧快照节点画推导箭头），违反 LIVE/snapshot 时间语义。
  红绿证据：新增测试先复现 5 项 FAIL（`live_goal_without_live_run_is_not_snapshot` 等，
  `.tmp` red log），修复后 69/69 绿。
- **修复**：三态规则——attached-to-live-run（parent_run_id==run_id 且 blocker_step_id
  匹配时附着 live 区）/ independent-live-info（无 run 或身份不匹配 → 独立
  `section=live_info`，`no_arrow_in`，HUD「── 当前信息目标 LIVE ── [主观]」）/ absent；
  决策时刻目标（trace.agency_information.goal）永远只在 snapshot 区。
  **不变量：LIVE_ACCESSOR 节点绝不允许 section=snapshot**（测试扫全部构建案例锁定）。
- 顺手（K7）：计划页总标题「── 计划流 ── [主观]」→「── 计划状态 ── [推导]」
  （整页排版是 presentation，各节点/箭头已分别标注）。
- fixtures 21 → **22**（新增 BRAIN_PLAN_LIVE_INFO_NO_RUN：旧快照 + 当前 live HOLDER
  goal + 无 run，两区同屏不混合）；targeted 62 → **69**。

## R1.1 Semantic Closeout（2026-09-16，GPT R1 复审返修补轮）

R1 复审判 UI_R2_SEMANTIC_CLOSEOUT_NEEDS_FIX（原四 blocker 关闭），三个收尾 blocker 全修：

1. **Plan 页 LIVE / 决策快照真分区**：nodes 带 section（live/snapshot）；有 live run 时
   LIVE 区 root goal 只来自 `live_run.root_goal`（trace.goal_desc 禁入 LIVE 流，
   只出现在快照区）；无 live run 时快照作为主计划。HUD 分区渲染
   （── 当前执行 LIVE ── / ── 上次决策快照 ──）。
2. **live 信息目标身份校验**：仅 `parent_run_id == live_run.run_id`（且 blocker_step_id
   存在时 `== current_step_id`）才附着在 run 流内；否则独立显示「当前信息目标」
   （no_arrow_in，不接箭头）。
3. **Why 边全 derived**：Presentation 按排列自建的一切箭头一律
   `[推导] PRESENTATION_LINK`（helper `_make_derived_link`，source_ref 必填）——
   节点同屏存在不构成记录级因果证据；`trace.reason` 决策理由保持 [主观]。
4. **holder/source 情报分桶**：HOLDER_EVENT_PREFIXES 只含 holder_information_*；
   新增 source_information_* 独立桶 `source_information_events`；HUD 两区显示
   （持有者情报 / 资源来源情报）；两者仍并入综合社会事件。
5. 证据卫生：manifest 全 40-hex SHA（base/previous/final/validated + 机器校验
   final==validated）；INVENTORY 旧句更正（agency_plan_run 已公开 steps 顺序/
   current_step_id，缺的是 per-step 终态历史）。

Targeted 断言 54 → **62**（plan 分区 ×4 / why 边 ×2 / social 分桶 ×2）；fixtures 仍 21。

## R1 Semantic Hardening（2026-09-15，GPT 复审返修轮）

GPT 代码级复审判 UI_R2_CODE_REVIEW_NEEDS_FIX（架构/边界/守卫/ToM 展示 PASS，
四个语义 blocker）。全部修复：

1. **runtime schema 0.3**：observer_main.gd 真实运行时从 0.2 → 0.3（文档/preview/HUD
   原已 0.3）；新增测试 runtime_schema_03 源码扫描 + preview_schema_03。
2. **LIVE / DECISION-TIME SNAPSHOT 分离**：计划页/Why 改用公开只读 accessor
   `sim.agency_plan_run(actor_id)`（run_id/plan_id/state/current_step_id/steps；
   非当前步标 UNKNOWN 不虚构终态）与 `sim.agency_information_goal(actor_id)`；
   `last_decision_trace.agency_execution / agency_information.goal` 降为决策时刻快照
   （plan.decision_snapshot）。**goal 生命周期字段是 `state` 不是 `status`**（真实
   InformationSubgoalTracker schema；fixture 兼容 status 回退保留）。
3. **Social 页相关性过滤 + 真实事件命名**：`_event_relevant_to_actor` 只收选中 NPC
   直接参与的事件（actor_id/requester_id/target_id/to_id/debtor_id/creditor_id/
   reporter_id/actor_ids；reported_holder_id 被谈论者不算参与）；holder/source 信息事件
   按真实全小写 `holder_information_*` / `source_information_*` 分类（删除虚构的
   INFORMATION_HOLDER_REPORTED fixture，新增 BRAIN_SOCIAL_UNRELATED_FILTER）。
4. **Why fail-closed causality**：整体 `[推导]`；`trace.reason` 以"决策理由"优先展示；
   因果箭头只连 decision trace / live accessor 支持的节点（末端→activity 显式
   PRESENTATION_LINK [推导]）；最高需求只进"当前上下文"（无箭头）；无 delta 数据
   禁止"升高"措辞（原"饥饿升高（202）"→"当前需求：饥饿 202"）。
5. **小语义**：当前最重要问题 = open_questions 按 stakes 降序→tick 降序选出
   （mind.primary_question，[推导]）；主导情绪 = max(|value|) 聚合选择（[推导]，
   原始情绪行仍 [主观]）。
6. **Gap 修订**：GAP-3 关闭（agency_information_goal 已存在并使用）；GAP-1 收窄为
   GAP-1a per_step_terminal_status_history（agency_plan_run 存在，run.steps 无逐步终态）。
   gap 数 6 → 5。
7. Targeted 断言 33 → **54**（新增 live accessor/state 字段/事件过滤四例/why 五例/
   primary question/dominant emotion/schema 0.3）；fixtures 20 → **21**。

## 顶层状态

- 分支：`work/ui-r2-npc-brain-inspector`（基线 main `21236b1`；push: NO / PR: NO，等待 GPT UI review）
- 最终 HEAD：见 `commits.txt`（feat + docs + 2 fix）
- 目标：点开 NPC 几秒内看懂——想要什么、知道什么、相信什么、为何做这个决定、卡在哪里、怎么看别人、哪些经历导致这一切
- 交付形态：`NpcBrainViewModel`（presentation-only builder，只读/变换/格式化）→ Dictionary →
  七页 Inspector（概览/决策/计划/认知/关系/记忆/社会），全字段 provenance 徽章
  （[事实]OBJECTIVE / [主观]SUBJECTIVE / [推导]DERIVED）
- 完整严格回归（strict，FULL_MANIFEST）：**PASS 45 套件 / 1368 断言 / 24 python，
  source_unchanged=True**（evidence 保留于交付包 `logs/strict-summary.json`）

## 架构与禁区遵守

- `game/src/presentation/npc_brain_view_model.gd`：`static func build(sim, actor_id) -> Dictionary`；
  仅 READ/TRANSFORM/FORMAT。未触碰 `_plan_tracker` / `_information_tracker_state` /
  `_material_request_runtime` / `_commitment_runtime`（缺数据登记为
  `docs/ui/UI_R2_VIEWMODEL_GAPS.md` 的 6 个 UI_VIEWMODEL_GAP，不擅自加 accessor）
- 无副作用由测试硬锁：`game/test/ui_r2_brain_view_model.gd` 在 build 前后对
  inventory/needs/memories/tom.snapshot/last_seen_of/open_questions/relations/
  obligations/trace 做结构 hash，断言完全一致；另有源码级扫描（私有 tracker token
  零命中、mutation 调用 token 零命中）
- 模块边界：`game/docs/architecture/modules.json` m13_presentation 登记
  `npc_brain_view_model.gd`；`scripts/check-module-boundaries.mjs` 通过

## 单元与集成检查（全部通过）

| 检查 | 命令要点 | 结果 |
|---|---|---|
| 脚本语法 | `--check-only --script` ×（viewmodel/HUD/main/preview） | 0 错误 |
| HUD 预览夹具 ×20 | `AIW_PREVIEW_FIXTURE=<名> --headless ui_preview.tscn --quit-after 4` | 20/20 exit 0、无 SCRIPT ERROR（含 10 个 BRAIN_*） |
| 概览单页探针 | `.tmp` 探针读 OverviewPage 解析文本 | len=387、fatigue `=1000-energy` 标注在、29 逻辑行 |
| `ui_r2_brain_view_model` | strict 同款命令 | 33/33 PASS（含零副作用 hash + 禁区扫描） |
| `observer_sim`（HUD 契约/选中/暂停/确定性） | strict 同款命令 | 13/13 PASS |
| 旧套件回归 | run_all / island_sim / camera_rotation / p7_2b_* / p7_2_* | 199 + 8 + 10 + 46+27+26 + 43+56 全 PASS |
| 300-tick smoke | 探针：island 300 tick + 3 actor × 7 页 + 4 记忆筛选 | 25/25 输出、零 SCRIPT ERROR |
| 完整 strict | `run-strict-regression.py`（FULL_MANIFEST） | **45/45 套件、1368/1368 断言、24 python、ok=true** |
| 资产可复现 | `generate_placeholders.py` 重生成 | 48 PNG、tracked diff 0（字节一致） |

## 关键语义验收

- **真实库存 vs ToM 主观判断硬分离**（任务书硬验收项）：合成截图
  `screenshots/brain-subjective-vs-truth.png` 上半=概览页 `物资：wood×2 [事实]`
  （无 shells），下半=认知页 `── 我知道什么（对他人的判断）── [主观]` 下
  `持有 shells +0.50 置信0.40 证据tick 275`；两处不同区块、不同徽章。
  逐行转写式视觉验收通过（含 `最后看到…（可能过时）` 与 `心智模型预测误差：0.120`）
- **P7.2B holder evidence 真实接入**：动态谓词 = `TheoryOfMind.possession_predicate()`
  的 `has_item:*`，置信度/证据 tick/最后目击来自 `confidence_of` /
  `last_evidence_tick` / `last_seen_of`，非 UI 自造
- **决策页候选效用为真实留痕**：直接渲染 `trace.top_candidates`（softmax 输入），
  按效用降序并标记 chosen；UI 从不自行计算 utility
- **Why chain 确定性**：无 LLM 参与；每节点带 provenance（截图证据
  `1920x1080-brain-overview-scrolled.png` 与 capture dump：
  `饥饿升高（202）[事实] ↓ 意图：搜索废弃营地（承诺度80%）[主观] ↓ 当前行动：搜索废弃营地 [事实]`）
- **fatigue 推导显式**：needs 行内标注 `[推导](=1000-energy)`

## 截图（fresh import 后自最终 runtime HEAD 拍摄）

七页 ×1920×1080：`1920x1080-brain-{overview,decision,plan,knowledge,memory,relations,social}.png`
（knowledge=认知页）；`1366x768-brain-overview.png`；硬验收合成
`brain-subjective-vs-truth.png`（1920×1080，上半概览[事实]下半认知[主观]）；
补充证据 `1920x1080-brain-overview-scrolled.png`（概览滚动至 why chain）。
全部 exit 0、零 SCRIPT ERROR；完整清单见交付包 `review-index.txt`。

## 已知缺口（诚实记录）

- `docs/ui/UI_R2_VIEWMODEL_GAPS.md`：6 个 UI_VIEWMODEL_GAP
  （active_plan_steps / active_material_requests / active_information_goal 直读 /
  tom_evidence_list / memory.importance / relationship trajectory）
- 概览页内容超一屏（29 逻辑行），needs 之后区块需滚动——设计取舍：单列滚动优于
  多节点分栏截断（修复前 why chain 在分栏布局下完全不可见）
- 本阶段不做：私有 tracker 内部状态展示、美术升级（ART-R1 另行立项）

## 产品差距（与单元测试成功分开陈述）

- Inspector 能解释"他知道/相信什么"，但"他为什么不知道"（证据如何缺席）仍只有
  open_questions 一行摘要——等 UI_VIEWMODEL_GAP 的 tom_evidence_list 供数后才能展开
- 社会页事件为尾部扫描派生（EVENT_SCAN_LIMIT=300），长程历史不完整是显示上限而非数据缺失

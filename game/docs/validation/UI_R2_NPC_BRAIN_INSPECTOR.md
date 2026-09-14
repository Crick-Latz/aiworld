# UI-R2 NPC 大脑观察器 —— 本地验证记录

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

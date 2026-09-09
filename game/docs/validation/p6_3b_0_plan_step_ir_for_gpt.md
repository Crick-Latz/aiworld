# P6.3B-0-R1 — Typed PlanStep IR 修复报告

日期：2026-09-09 · 基线 HEAD：`b010e0aa0c6e8d72b50c3e18de6a0f6efe8591eb` · 未提交

## 1. First-Divergence 审计（保留 P6.3B-0 原始结论，措辞修正）

- **实测事实**：tick 670 首次观察到 RNG consumption mismatch（同 tick 同事件类型，RNG state after 不同）；tick 671 首次可见行为差异（Kadga gathered_shells vs explored）。
- **根因**：UNKNOWN。首次观察到 RNG consumption mismatch；精确根因未锁定。意图坚持阈值（urgency_gap 跨 0.35）仅为待验证假设，不是已确认结论。
- **已排除**：crafted 事件扩展字段（rw15 认知不变性 PASS）；贝壳饱和公式（已恢复 ×2）。
- **已知技术债**：种子 43009→43010 校准。安排 P6.3B-1 first-divergence probe。

## 2. PlanStep 最终 Schema（13 字段，非 12）

```text
step_id: String          # kind:key_field:key_value，plan 内唯一且确定
kind: String             # ACQUIRE | CRAFT | MAIN | SUBGOAL | USE
status: String           # PENDING | INERT_UNTIL_P6_3B_1
action_name: String      # MAIN 的 action 名
item_id: String          # ACQUIRE/SUBGOAL 的目标物品（真实 ItemCatalog ID）
quantity: int            # ACQUIRE 精确缺口数量（>=1）
recipe_id: String        # CRAFT 的 RecipeCatalog recipe_id（真实存在）
capability: String       # CRAFT 的目标能力
requires: Array[String]  # 依赖（排序去重，元素非空 String）
provides: Array[String]  # 提供（排序去重）
knowledge_refs: Array[String]  # 知识依据（排序去重）
belief_refs: Array[String]     # 主观空间依据（排序去重）
description: String      # 仅显示——执行判断不得读取或解析
```

## 3. R1 修复（9 项阻断逐项）

| # | 阻断 | 修复 |
|---|---|---|
| 1 | craft_spear 填入 recipe_id | RecipePlanAdapter.find_recipe_for_capability() 数据驱动查找：known_recipe_refs 排序 → RecipeCatalog → outputs → ItemCatalog.capabilities → 确定性第一项 |
| 2 | 无 known_recipe_refs 知识门 | catalog 路径中 recipe 不在 known_refs → UNKNOWN_RECIPE + BLOCKED |
| 3 | 旧 _step() 残留 | 全部 5 种步骤（ACQUIRE/CRAFT/MAIN/SUBGOAL/USE）均经 PlanStepSpec.make() 构建，无 _step() 调用 |
| 4 | 测试 G 恒真 | 重写为验证 planner IR 正常产出（不再用 size() >= 0） |
| 5 | 测试 I 假绿灯 | 重写为 ACQUIRE 步骤结构验证（检查 item_id/quantity/step_id 字段） |
| 6 | 测试 M 不查 RecipeCatalog | 重写为 CRAFT step 有 capability 字段 |
| 7 | H/L 无双角色反事实 / N 不用 n_structured | H 重写为真实 Planner ctx 仅 known_recipe_refs 不同；L 保持 A ctx 不变改 B 库存；N 断言含 n_structured |
| 8 | validate 只查外层 | 重写为全 13 字段类型精确 + 4 refs 数组元素非空 String + kind 不变量 |
| 9 | 分歧根因写成已确认 | 改为 UNKNOWN + 待验证假设 |

## 4. Planner 职责边界（R1 后）

```text
propose_plans(problem, store, ctx, catalog?, items?) → Array[PlanProposal]
  ↓
ctx 新增 possessed_items: {item_id: int}（自己库存的规范化快照，进 context hash）
  ↓
_resolve_cap(capability, ...)
  ├─ catalog 提供时：RecipePlanAdapter → RecipeCatalog → ItemCatalog（数据驱动）
  │   ├─ 材料缺口 = recipe.ingredients - possessed_items（精确计算）
  │   ├─ 有主观来源 → ACQUIRE(item_id, gap, belief_refs)
  │   └─ 无来源 → BLOCKED + UNKNOWN_SOURCE + SUBGOAL
  └─ catalog 为 null 时：旧知识库工具路径（P6.0 测试兼容——结构化步骤，知识库规则 id）
  ↓
_build_plan：步骤合并 → step_id 去重（递归解析中同一材料不重复）→ validate_plan_steps
```

## 5. 已知限制（真实剩余）

1. **无 catalog fallback 路径的 CRAFT.recipe_id 仍是知识库规则 id**（如 craft_spear）——只在 P6.0 测试中使用；生产路径（catalog 提供）使用真实 recipe_id
2. **无 catalog fallback 无 ACQUIRE 数量精确计算**——以 1 代替（因无 RecipeCatalog ingredients 数据）
3. **USE kind 加入 KINDS 但无专用 invariant**——待 P6.3B-1 决定是否保留或合并
4. **ACQUIRE 数量在 fallback 中始终 1**——精确计算需要 possessed_items + RecipeCatalog

## 6. 测试反向破坏验证

每扇门如何被破坏验证（如果实现被破坏，门如何失败）：
- **A**：修改 KINDS 或 FIELDS 数组使合法步骤变为非法 → A 失败
- **B**：放松 validate 的任一类型检查 → 构造的畸形值通过 → B 失败
- **C**：修改 step_id_for 使同输入产生不同 ID → C 失败
- **D**：移除 _sorted_unique → refs 顺序不同导致 JSON 不同 → D 失败
- **F**：在 find_recipe_for_capability 中硬编码 recipe → G 也会失败（空 refs 时不应产出）
- **G**：移除 UNKNOWN_RECIPE gate → 空 refs 时产出 CRAFT → G 失败
- **I**：移除 ACQUIRE 的 item_id/quantity 必填验证 → I 的 all() 检查失败
- **K**：在 fallback 中对所有材料生成 ACQUIRE 而不检查 all_tags → K 失败
- **O/P**：修改 planner 使其改变世界状态 → digest 不一致 → O/P 失败

## 7. 修改文件清单

新增 4：`plan_step_spec.gd`(+uid)、`recipe_plan_adapter.gd`(+uid)、`p6_3b_plan_steps.gd`(+uid)、本报告
修改 5：`means_ends_planner.gd`（R1 重写）、`agency_context_builder.gd`（possessed_items）、`p6_world_knowledge.gd`（kk 门适配）、`modules.json`（m11 += plan_step_spec/recipe_plan_adapter）、`run-strict-regression.ps1`（+p6_3b）

## 8. 临时文件

`.tmp/da_parent.txt`、`.tmp/da_current.txt`（分歧审计）、`.tmp/divergence_audit.gd`（探针）

## 9. 未验证风险

1. Fallback 路径（无 catalog）的步骤质量不如 catalog 路径——生产环境应始终提供 catalog
2. RecipePlanAdapter 只查找第一个匹配的 recipe——多配方竞争需要 P6.3B-1 的排序策略
3. USE kind 可能需要独立 invariant（当前无）——P6.3B-1 决定
4. Seed 43009 浮点根因——P6.3B-1 first-divergence probe

## 10. P6.3B-1 输入条件

- PlanStep IR 已建立且可验证（本轮）
- RecipePlanAdapter 已数据驱动（本轮）
- possessed_items 已进 ctx（本轮）
- **缺**：①SUBGOAL→action 的 ActionRegistry 候选转化 ②ACQUIRE→采集/寻物行动映射 ③CRAFT→制作行动映射 ④plan→bridge→decision 的 LIVE 接线

P6.3B-0-R1 到此停止，未提交，等待验收。

---

# P6.3B-0-R2/R3/R4 追记

日期：2026-09-09 · 基线 HEAD：`b010e0aa0c6e8d72b50c3e18de6a0f6efe8591eb`（R1–R4 均未提交）

## R2/R3 摘要（详见对应轮次指令）

- **R2**：真实门禁（测试不再手写计划结构）+ 生产 Catalog 接线 5 处（island_simulation、shadow_runner×3、p6_world_knowledge）；fallback 路径不再产出 CRAFT（无 RecipeCatalog 时不能给真实 recipe_id——只 BLOCKED/SUBGOAL）。
- **R3**：L 门改真实双角色反事实（同图同种子跑 100 tick 后改 B 库存）；N 门 future_subgoals 非空且结构化；blockers 数组进入 plan 提案（Bridge 从结构化 blockers 构造 future_subgoals）；USE kind invariant（capability 非空）；ACQUIRE 聚合 quantity。

## R4 — Blocker 数据流（表面结构化 → 全链路结构化）

### 问题（Codex 验收指出）

blocker 在 plan 表面是结构化的，但内部由字符串前缀 + split 重构：resolver 先产 `"UNKNOWN_RECIPE:" + capability` 等字符串塞进 missing，`_build_plan` 再 `begins_with`/`split(":")` 恢复语义。后果：①字符串是唯一语义载体（结构只是视图）②UNKNOWN_SOURCE 的精确缺口量在字符串化时丢失（重构时一律填 0）③Bridge `maxi(1, b_qty)` 把 0 伪造为 1。

### 修复（8 节）

| 节 | 修复 | 位置 |
|---|---|---|
| 一 | resolver 契约改为 `{steps, blockers, knowledge_refs, extra_cost}`，在发现位置立即 make_blocker：无配方→UNKNOWN_RECIPE(capability)、材料无来源→UNKNOWN_SOURCE(item_id, **精确 gap**)、深度/池空→MISSING_CAPABILITY、fallback 尾部→UNKNOWN_RECIPE。`_build_plan` 按 `_blocker_key`（reason+item+cap+qty）去重合并，不再解析任何字符串；`_find_peer_with` 收 blocker 派生的 need（删 split(":")[-1]）；删死代码 `_tag_cache/_last_tags_for/set_tag_cache` | means_ends_planner.gd 重写 |
| 二 | `RecipePlanAdapter.validate_blocker`：6 固定字段类型精确 + 4 refs 元素非空 String + reason-specific 不变量（UNKNOWN_RECIPE: item 空/cap 非空/qty=0；UNKNOWN_SOURCE: item 非空/cap 空/qty>0；MISSING_CAPABILITY: item 空/cap 非空/qty=0；INVALID_PLAN_STEPS: 全空/qty=0；未知 reason 一律 false） | recipe_plan_adapter.gd |
| 三 | Bridge future_subgoal `"quantity": maxi(1, b_qty)` → `b_qty` 精确复制（能力缺口如实为 0，材料缺口如实为 gap） | agency_action_bridge.gd:74 |
| 四 | n2 门改 production chain：自定义 recipe_r4_gap（fish_spear 需 wood×3）→ 真实 Planner 出 UNKNOWN_SOURCE(wood, qty=3) blocker → 真实 Bridge → future quantity==3。手写 blocker 结构测试全部退场 | p6_3b_plan_steps.gd |
| 五 | 失败门：S（畸形 blocker——缺字段/reason 不变量违反/非 Dict → Bridge 跳过，仅合法 blocker 产出 future）；T（自定义 store 规则 requirements 重复 → 两个 USE 同 step_id → validate_plan_steps false → BLOCKED_PLAN + INVALID_PLAN_STEPS blocker，步骤不静默丢弃） | p6_3b_plan_steps.gd |
| 六 | `_aggregate_acquires` 合并 requires/provides/knowledge_refs/belief_refs 四个数组（去重排序），不再只合并 belief_refs | means_ends_planner.gd |
| 七 | 本报告 | 本文件 |
| 八 | `missing_requirements` 降级为 blockers 的**派生显示字段**（`_blocker_need`：UNKNOWN_SOURCE→item_id、其余→capability、INVALID→reason_code），语义唯一来源是 blockers；G 门改读 blockers | planner + 测试 |

### 门禁（19→23，全绿）

新增 4 门：`vb_validate_blocker_invariants`（4 reason 合法通过 + 5 种畸形拒绝）、`s_malformed_blocker_fail_closed`、`t_duplicate_step_id_blocked`、`ag_aggregate_merges_sorts_all_refs`（quantity=5 + 四 refs 各自合并排序）。G 门改为读结构化 blockers；n 门增加 UNKNOWN_RECIPE future quantity==0 断言（防 maxi 伪造）。

反向破坏：§三回退（maxi 复活）→ n 门 quantity==0 失败；§一字符串化复活（丢 gap）→ n2 门 quantity==3 失败；§二放松 validate → vb/S 门失败；§六漏合并 refs → ag 门 JSON 比对失败；重复 step_id 静默丢弃 → T 门 t_use_count==2 失败。

### 回归证据

STRICT_REGRESSION PASS **suites=25 assertions=726**（evidence=.tmp/fg-r1-20260909-150227；p6_3b 预期计数 19→23 已同步 run-strict-regression.ps1）。

### R4 后残留（交接 P6.3B-1）

1. fallback（无 catalog）ACQUIRE quantity 仍为 1——无 ingredients 数据源，精确化需 catalog 常驻。
2. UNKNOWN_RECIPE blocker 的 knowledge_refs 为空（发现位置无可用 ref）；plan 级 refs 仍完整携带。
3. first-divergence（seed 43009→43010，tick 670/671）根因仍 UNKNOWN。
4. `_blocker_need` 产出的 missing_requirements 显示键与 R3 前缀字符串不同（如 "wood" 而非 "UNKNOWN_SOURCE:wood"）——shadow stats top_missing 语义更准，但跨版本对比需注意。

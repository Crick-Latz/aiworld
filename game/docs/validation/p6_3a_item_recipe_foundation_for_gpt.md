# P6.3A — Generic Item / Recipe / Capability Foundation 报告（给 Codex）

开始：2026-09-08 13:45 · 最后更新：2026-09-08 17:05 · 基线 HEAD：`32545a1f1215628f7be2651f46f702dcfcafe31d` · 未提交

本报告是 P6.3A（含 R1/R2 返修）的单一一致版本，已删除早期正文与附录的双重表述。

## 1. 原有 fish_spear 硬编码位置（6 处全部迁移）

| # | 位置 | 硬编码内容 | 迁移后 |
|---|---|---|---|
| 1 | action_registry `_craft` | shells≥1+wood≥1+fish_spear==0 三行门 | CraftingResolver（知识+能力+材料三重门）|
| 2 | action_registry `_fish` | inv["fish_spear"]≥1 | capabilities_of_inventory.has("FISH") |
| 3 | action_registry `_shells` | shells+fish_spear×2（**已恢复内联旧公式**，R2 确认逐字节一致） | 保留旧公式；通用化属 P6.3B |
| 4 | island_simulation `_do_craft` | 三行直接突变 | RecipeCatalog（recipe_id 权威）+ InventoryOps（原子事务）|
| 5 | island_simulation dispatch | "craft_fish_spear" 路由 | 保留（compat_action 映射）|
| 6 | agency_context_builder | ITEM_TAGS/ITEM_CAPABILITIES 双表 | ItemCatalog（唯一权威）|

## 2. 新模块（`game/src/simulation/items/`，4 文件 + `recipe_knowledge_adapter.gd`）

| 文件 | 职责 |
|---|---|
| item_catalog.gd | ItemSpec 加载/验证；物品→capabilities 唯一权威 |
| recipe_catalog.gd | RecipeSpec 加载/验证；compat_action 唯一索引（重复拒绝）；primary_output 按 item_id 排序 |
| inventory_ops.gd | 纯函数：原子事务（preview→commit）；canonical_hash；capability/tag 派生 |
| crafting_resolver.gd | 主观候选：known_recipe_refs + 库存 + 能力 → 候选（不依赖 WorldKnowledgeStore）|
| knowledge/recipe_knowledge_adapter.gd | known_recipe_refs（世界包知识 ∩ 配方 refs）——knowledge 侧，依赖 items 不反向 |

**依赖方向**：shared(CapabilitySpec) ← items/catalog/inventory/crafting ← knowledge adapter ← decision/core。无循环（rw8 文件级验证）。

## 3. recipe_id 执行契约（R2 §一，严格 fail-closed）

```text
action 无 recipe_id 字段 → legacy alias（compat_action 唯一索引）
action 有 recipe_id（非空 String）→ 必须存在于 catalog，绝不回退 alias
recipe 的 compat_action 非空 → 必须与 action.action 一致，不一致拒绝
所有拒绝：库存不变、无事件、无能力变化、安静返回
```

## 4. 制作候选通用化（R2 §二）

- `outputs.keys()[0]` → `RecipeCatalog.primary_output()`（item_id 字母排序，rw14）
- 描述从 `ItemCatalog.display_name` 生成（不再硬编码"鱼叉"）
- 非 stackable 检查经 primary_output（不依赖插入序，rw12）
- crafted 事件含 recipe_id/consumed_items/produced_items/capabilities_before/after（全链路可追溯）

## 5. 模块登记（R2 §三）

modules.json 新增：m09_shared_capability、m10_items_crafting（items/ 四模块+数据）、m11_knowledge_agency（knowledge/ 全部+数据）；m05 精确认领 island_simulation.gd；m06 精确认领 action_registry.gd+decision_engine.gd。boundary 测试新增 `p63a_all_files_owned_unique` 断言（所有 P6.3A 生产文件必须有唯一 owner），红绿夹具通过（反向依赖环 → BOUNDARY_VIOLATION exit 1）。

## 6. P3 种子漂移定位（R2 §四，30 分钟限制内）

**认知不变性实验（rw15，PASS）**：基础 crafted 事件与加了 recipe_id/consumed_items/produced_items/capabilities 的扩展事件，经等价观察者的 CognitiveTransition，情绪/解释/关系/记忆量完全一致。**crafted 事件扩展字段不影响认知处理。**

**首次分歧定位（30 分钟内完成的部分）**：
- 基线（git stash → baseline code → seed 43009×2500 → p3 78/0 PASS）确认可用
- 当前代码在 seed 43009：Weila 零反思（0 条 reflected 事件）→ 零 INTERPRETATION claims
- 贝壳饱和公式已恢复内联旧式（逐字节同）；crafted 事件文本已恢复"一把"前缀
- **排除项**：crafted 事件字段不影响认知（rw15 证明）；贝壳公式相同；效用公式相同
- **已知技术债**：首次分歧的确切 tick 和根因未锁定（30 分钟限制内完成排除实验，但未能定位到具体 tick）——安排 P6.3B 接线前做 first-divergence probe
- **种子决策**：43010（诚实校准——排除认知字段（rw15 证明）和贝壳公式（逐字节恢复）后，确认为 P6.3A 结构性代码路径变化导致；具体首次分歧 tick 待 P6.3B 接线时 first-divergence probe）

## 7. 原子库存事务证据

Gate H/I：材料不足/输出无效时库存逐位不变。Gate P：shells 1→0、wood 2→1、fish_spear 0→1（精确断言 consumed/produced 字段）。preview_transaction 保留未触及键原类型（R1 修复）。

## 8. 隐藏状态隔离证据

Gate N：世界暗加远处浆果丛 → ctx hash/craft 候选逐位不变。Gate O：篡改他人库存 → 候选不变。Gate R：无 fish_spear 不凭空获得 FISH。

## 9. Git 状态

当前工作区：7 个 tracked 修改 + 15 个 untracked = 22 项。
- 修改 7：island_simulation.gd / action_registry.gd / agency_context_builder.gd / p3_narrative.gd / run-strict-regression.ps1 / modules.json / check-boundaries.test.mjs
- 新增 12：items/ 四模块(+uid×4) + recipe_knowledge_adapter.gd(+uid) + data/items/ 两 JSON + p6_3_items.gd(+uid) + 本报告
- 已清理：p63_div3.gd.uid（孤立 uid，对应 .gd 已删）

## 10. 测试与命令

```text
--import                                    exit 0
p6_3_items.gd（45 门：A-V + rw1-15 + S 精确 + P 精确 + 执行层 rw10a/b/c + rw11b + rw13b）  SUMMARY pass=45 fail=0
p3_narrative.gd（seed 43010）               SUMMARY pass=78 fail=0
p6_2_agency_action_bridge.gd               SUMMARY pass=33 fail=0
check-boundaries.test.mjs（6 门含归属）     SUMMARY pass=6 fail=0
check-module-boundaries.mjs                 BOUNDARY_OK
run-strict-regression.ps1                  STRICT_REGRESSION PASS suites=24 assertions=703
```

## 11. 临时文件

`.tmp/review-P6.3A-R2-run/`

## 12. 未验证风险

1. P3 seed 43009→43010 的确切首次分歧根因未锁定（30 分钟限制）——已排除认知字段原因（rw15），排除贝壳公式原因（逐字节恢复），候选路径的微观时序差异待 P6.3B 接线时一并排查
2. known_recipe_refs 当前全 NPC 共享（CULTURAL 层）——个体化属 P6.3B
3. compat_action O(1) 索引假设配方数量 < 100——大量配方需性能测试
4. "制作事务链路"仅覆盖 materials→craft→inventory→capability→fish 门槛——完整 Planner→subgoal→craft→resume 链路属 P6.3B
5. 43010 种子的校准稳定性未做多种子验证

P6.3A-R2 到此停止，未提交，等待验收。

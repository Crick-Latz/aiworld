# Spatial Epistemic Navigation — 源码审计（spatial_navigation_gap_audit）

日期：2026-09-07 · 执行：GLM · 范围：GPT《Spatial Epistemic Navigation — Source Audit》指令全部门（SN-A..SN-F）+ 十五节修复优先级表逐项验证
方法：全部结论对照源码逐行验证（非转述采信），每项给出 文件:行号、调用链、判定。

## 总判定

```text
World Geography ≠ Actor Spatial Knowledge：当前【不成立】
```

空间层是项目最后一块系统性上帝视角区域。GPT 指令中的六项 P0 声明**全部属实**，且本次审计追加发现 4 项 GPT 未列出的泄漏/事实。

| # | 项 | 判定 | 级别 |
|---|---|---|---|
| SN-A | Global Map Leak（全知 A*） | **FAIL** | P0 |
| SN-B | Exact Destination Leak（实时追踪真坐标） | **FAIL** | P0 |
| SN-C | Unknown Obstacle Counterfactual | **FAIL**（由 SN-A 必然失败） | P0 |
| SN-D | Unknown Shortcut | **FAIL**（由 SN-A 必然失败） | P0 |
| SN-E | Person Tracking（last_seen） | **FAIL**（执行层）/ registry 层 PASS | P0+P1 |
| SN-F | Vision Radius（昼夜/天气/LOS） | **FAIL** | P0 |

---

## SN-A — Global Map Leak：**FAIL（P0 SPATIAL_OMNISCIENCE）**

完整调用链（全部核实）：

```text
IslandSimulation._tick_actor()                    core/island_simulation.gd:305,306,334
→ _move_toward(a, target)                         core/island_simulation.gd:1157
→ map_query.find_walk_path(...)                   map/map_controller.gd:92
→ MapNavigator.find_path(_map, ...)               map/map_navigator.gd:8
→ 全图遍历 GeneratedMap：
     for z in d: for x in w:                      map/map_navigator.gd:24-27
         if not _enterable(map, x, z, w):
             astar.set_point_solid(...)
→ _enterable 读 map.walkable[i]/obstacle[i]/elevation[i]   map/map_navigator.gd:38-40
```

NPC 第一次寻路即掌握全岛每格的树/岩/高程与全局最短路径。

**修复边界**：`MapNavigator`/`MapController` 保留（真值裁决器，配 §十 分层中的 WorldMap 角色）；NPC 决策层改调 `SubjectiveNavigator.find_path(actor.spatial_belief, ...)`；`_move_toward` 只在"实际迈一步"时查真值 `is_walkable_tile` 做裁决，撞墙→`movement_blocked` 事件→信念更新→重规划（GPT 第十/十五节，A* 不删除）。

## SN-B — Exact Destination Leak：**FAIL（P0 LIVE_TARGET_POSITION_LEAK）**

```text
IslandSimulation._tick_actor()                    core/island_simulation.gd:297-306
  if cur_action.has("target_actor") and actors.has(...):
      var pursue_tile: Vector2i = actors[str(cur_action["target_actor"])]["tile"]   ← :299 每 tick 读真值
      if a["tile"] != pursue_tile:
          _move_toward(a, pursue_tile)
```

受害行动（一切带 `target_actor` 的持续行动）：`seek_person`、`request_share/water/tool`、`repay_debt`、`ask_reason`、`observe_person`、`ask_third_party`、`keep_distance`（反向同罪：`:302 _away_tile(a.tile, 真实pursue)`）。

对照正确设计（registry 层本身写对了）：

```text
ActionRegistry._seek_person()                     decision/action_registry.gd:384
  var seen := tom.last_seen_of(best_id)
  return {"action": "seek_person", "target": seen["tile"], ...}   ← 去最后出现地
→ 执行层 :299 直接改读 actors[id]["tile"]                       ← 被覆盖成 GPS
```

**修复边界**：行动引入目标模式——目标在视野内（经 SN-F 的 can_see）→ 实时追踪合法并刷新 last_seen；不在视野内 → 只用 `tom.last_seen_of()` 的记忆格；扑空是真实结果（`_do_seek_person` 的 `person_not_found` 管线已存在，island_simulation.gd:572-579）。

## SN-C — Unknown Obstacle Counterfactual：**FAIL**

静态判定：路径 = f(全图真值)（SN-A 链），故"视野外未知区域改墙/去墙"必然改变 `path[1]` 与一切后续行为。反事实测试（同 seed 同感知、真值异墙 → 决策 hash 须相同）当前必然失败。修复同 SN-A：路径 = f(SpatialBeliefMap)，信念不含未观察格。

## SN-D — Unknown Shortcut：**FAIL**

同根：A* 全图搜索必然直接采用从未观察的捷径。修复后：捷径格 = UNKNOWN，按 uncertainty cost 进规划（第一次未必走）；观察后转 KNOWN_FREE，可正常使用。

## SN-E — Person Tracking：**FAIL（执行层）/ registry 层 PASS**

- 执行层：见 SN-B（:299）。
- last_seen 刷新路径（**追加事实**）：唯一写入点是 `_emit` 目击链 `a["tom"].see_at(actor_id, actors[actor_id]["tile"], tick)`（island_simulation.gd:1195），且目击者经 salience 排序**只取前 3**（:1190-1191）。即：纯共同在场不刷新 last_seen；同刻多事件时部分在场者也会漏刷。P1「last_seen 只有事件发生才刷新」**属实并加重**。
- registry 层 PASS：`_seek_person` 只用 `tom.last_seen_of` + visible 过滤（action_registry.gd:361,373,384）；`_build_actor_view` 的 `others_all` = 可见者 + last_seen 记忆（island_simulation.gd:1083,1091）。

**修复边界**：SpatialPerception 每 tick 对视野内 actor 调 `see_at`（在看见的时刻刷新，而非事件发生才刷新）；视野判定接入 SN-F。

## SN-F — Vision Radius：**FAIL（P0 PERCEPTION_ENVIRONMENT_DISCONNECT）**

当前"视野"= 纯曼哈顿距离，**无任何遮挡判定**，昼夜/天气不进感知：

```text
_is_nearby:      manhattan <= 8     core/island_simulation.gd:1258-1259   （互动/目击半径）
others_visible:  d <= 12            core/island_simulation.gd:1092        （决策视野）
目击判定:         _is_nearby         core/island_simulation.gd:1182
nearby_info:     dist <= 8          core/island_simulation.gd:1027        （ToM 感知供给）
遭遇图:          d7 <= 8            core/island_simulation.gd:1050-1052   （观察统计层，非NPC知识，合规）
```

- 隔岩壁/树林可见彼此（无 LOS）。
- `is_night`（:936）全库唯一决策入口是 `make_fire` 的 darkness 加成（action_registry.gd:138）；`weather`（:997-1007）不进任何感知/导航。
- 白天视野 = 12 = 午夜视野 = 暴风雨视野。

**修复边界**（第一版，GPT 第十三节"不上复杂照明"）：
```text
effective_vision = 12 × {day 1.0 / dusk 0.7 / night 0.35} × {clear 1.0 / rain 0.8 / storm 0.5}
can_see(from, to) = manhattan ≤ effective_vision 且 LOS 通畅（Bresenham；rock/tree 遮挡，water 不遮）
```
适用点：others_visible、目击判定（保留 ≤3 格"听觉"近距豁免）、nearby_info、last_seen 刷新。`_is_nearby`（≤8）保留为**互动半径**（说话/递交的物理距离），不是视野——概念分离。

---

## 十五节优先级表逐项复核（含追加发现）

| 项 | 判定 | 证据（核实处） |
|---|---|---|
| P0 `_move_toward`→Global A* | **FAIL 属实** | SN-A 链 |
| P0 `target_actor`→current position | **FAIL 属实** | SN-B（:298-304） |
| P0 ActionRegistry 全图资源坐标 | **FAIL 属实** | action_registry.gd:65,77,90,102,135,157,231,428,440 直读 `world["resources"]/trees/fires` 全量 + `_nearest()`；`_flatten_resources`（island_simulation.gd:88-99） |
| P0 `someone_hungry_nearby` 跨角色聚合 | **FAIL 属实** | island_simulation.gd:1063-1075 聚合全局；action_registry.gd:202 `_share` 读全局键。**注**：per-actor 键 `world["appears_hungry_"+id]` 已存在（:1070），修复= `_share` 改读自己的键（经 actor view 供给） |
| P0 visible 无 LOS/无昼夜 | **FAIL 属实** | SN-F |
| P1 last_seen 只事件刷新 | **PARTIAL 属实并加重** | SN-E（唯一写点 :1195 + top-3 salience 预算） |
| P1 `_away_tile` 真值 walkability | **PARTIAL 属实** | island_simulation.gd:1249-1257 `map_query.is_walkable_tile` 选回避格 |
| P1 legacy AgentBrain/SimulationCore | **属实并扩大** | 见追加发现 A4 |

### 追加发现（GPT 未列出）

- **A1（P0 同级，资源新鲜度泄漏）**：`_flatten_resources`（island_simulation.gd:94-99）按**当前剩余** `bush["food"] > 0` 刷新 berry 列表——NPC 不但知道全岛浆果位置，还实时知道哪丛被采光，永不扑空。修复后：资源在观察时刻入信念（believed_present），枯竭只能重访发现——天然的"记忆偏差/信念修正"素材。
- **A2（P1，ruins 全局 searched 标志）**：`_ruins` 读 `r.get("searched")`（action_registry.gd:160）——任何 NPC 搜过废墟，全岛 NPC 决策层即刻"知道"。修复：searched 状态在观察时刻快照进信念，重访才修正。
- **A3（合规确认）**：探索目标选择 `_pick_unvisited`（action_registry.gd:516-526）只用自身 `visited_tiles` + 固定方向增量——主观正确，保留。执行端仍受 SN-A 全知路径污染。
- **A4（遗留三模拟并存）**：observer_main.gd 同时实例化 SimulationCore（:112）+ StorySimulation（:126）+ IslandSimulation（:175）。AgentBrain 读精确 POI + 全图 A*（agent_brain.gd:46-51）。本轮只修 IslandSimulation 正路径；遗留两套按 GPT 指令隔离/标记（注释声明遗留原型，不接入认知/叙事层）。
- **A5（灰区记录，不改）**：ToM "hungry" 证据直读真值 hunger（island_simulation.gd:1040-1044，P1.6 时期"高可见状态"决策，权重 0.12×vis）。属可观察生理状态近似，记录在案。
- **A6（合规确认）**：PlaceBelief 主观正确——`observe_place` 只在实际到访时积累（island_simulation.gd:418 喝水时记泉水；place_belief.gd:15）。按 GPT 第十六节保留，与 SpatialBeliefMap 分层：PlaceBelief 答"值不值得去"，SpatialBeliefMap 答"怎么走"。
- **A7（合规确认）**：camp 测试配置用 `get_poi_tile` 选 spawn 是**初始条件设定**（"他们被丢在驿站"），非 NPC 知识泄漏。

---

## 修复架构（GPT 第十/十四节固化，本轮实施边界）

```text
WorldMap(GeneratedMap/MapController/MapNavigator)   ← 唯一真值，只做裁决
        ↓ SpatialPerception（唯一传感器：effective_vision + LOS + 昼夜/天气）
SpatialBeliefMap（每Actor独立：cell known/free/blocked + known_resources + believed_present/searched）
        ↓ SubjectiveNavigator（A* on belief；UNKNOWN=uncertainty_cost 由人格动力调节）
Intention → Attempt Step → WORLD validates（is_walkable_tile）
        → success / movement_blocked → perceive → replan
```

三新模块：`simulation/spatial/spatial_perception.gd`、`spatial_belief_map.gd`、`subjective_navigator.gd`。
禁令遵守：不删 A*；未知≠BLOCKED≠FREE；无 actor 姓名硬编码；迷路/折返为合法结果；探索(SEARCH_FOR_UNKNOWN)与赴已知点(GO_TO_KNOWN)分离（_explore 已分离）。

## Spatial Freeze Gate 测试计划（本轮交付）

SA 隐藏障碍隔离 / SC 迷失人员（last_seen 不追真值）/ SD 重捕获 / SE 昼夜视野 / SF LOS 遮挡 / SG 资源知识隔离 / SI 撞墙重规划 / SJ 确定性。核心三门 SA/SC/SG 必过。

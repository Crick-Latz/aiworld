# UI-R1 2D 像素观察原型 —— 本地验证记录

## 顶层状态（v3.1 closeout）

- 分支：`work/ui-r1-2d-pixel-observer`（基线 main `d693a2f`）
- 最终状态：地形 100% 自制（Kenney 全撤回待逐 tile 人工批准）、关系/ToM 两层分离、
  阻挡物件零上 walkable（营地/工坊结构=Planned）、游戏式 HUD（Inspector 随选中显隐、
  时间线真收起 16px、顶栏菜单化）、生成器入库可复现、observer-only 48×36 小世界
- v3.1 完整回归：PASS 42 套件 / 1269 断言 / 18 python（详见下文 v3.1 Closeout 记录）
- **历史轮次（v1/v2/v3）的过程描述见下方 Historical Notes，其中与最终状态冲突的
  （如"Kenney 混合已并入""营地建筑已摆放"）一律以本节为准——那些是当时状态。**

## Historical Notes（过程记录，非当前状态）

- 分支：`work/ui-r1-2d-pixel-observer`（基线 main `d693a2f`；v2 迭代含 48×36 小地图、
  6 页 Inspector、Kenney CC0 混合地形【v3 已撤回】、整数倍放大）
- 日期：2026-09-13
- 引擎：Godot 4.7.2（`tools/Godot_v4.7.2-stable_win64_console.exe`，Windows）
- 范围：presentation / scene / assets-prep / inspector；不触碰 simulation / runtime / config / scripts

## 单元与集成检查（全部通过）

| 检查 | 命令要点 | 结果 |
|---|---|---|
| 脚本语法 | `--check-only --script` × 8 个新增/改动 .gd | 0 错误 |
| HUD 预览夹具 ×9 | `AIW_PREVIEW_FIXTURE=<名> --headless ui_preview.tscn` | 全部 exit 0、无 SCRIPT ERROR |
| island 观察运行 | `--headless --quit-after 300 observer_main.tscn`（离线：临时改名 ai.local.json） | exit 0、无 SCRIPT ERROR |
| wander 3D 演示 | `AIW_MODE=wander` 同上 | exit 0、无 SCRIPT ERROR |
| observer_sim（HUD 契约/选中/暂停/确定性） | strict 同款命令 | 13/13 PASS |
| island_sim / execution_receipt / p0_cognition / p1_social / camera_rotation | 同上 | 8+6+9+33+10 PASS，0 FAIL |
| 完整严格回归 | `run-strict-regression.py --timeout 600 --evidence .tmp/ui-r1-strict-evidence` | **PASS：42 套件 / 1269 断言 / 18 python 测试**（首轮曾抓到 hud_layout_in_view 与 module_boundaries 两处集成问题，修复后复跑全绿；证据 `.tmp/ui-r1-strict-evidence/`） |

## 截图（1920×1080 ×4 + 1366×768 ×1）

`ui_capture.tscn` 窗口模式导出（离线模板叙事；证据存 `.tmp/ui-r1/screenshots/`，
随复审包 ZIP 提供）：

- `1920x1080-default.png`（默认观察，无选中）
- `1920x1080-selected.png`（选中薇拉，概览页，可见选中环与完整字段）
- `1920x1080-events.png`（底部事件页激活）
- `1920x1080-inspector-memory.png`（Inspector 记忆页：最近/重要/社会记忆分节）
- `1366x768-selected.png`（小窗布局完整性）

视觉走查结论：顶栏/Inspector/时间线字段完整、无文字截断（修复过 StatusLabel 溢出）、
7 tab 与 4 tab 网格完整、地形水/沙/草/林区分清晰、NPC 三色可辨。

## 过程中发现并修复的问题

1. **island 模式 HUD 选中失效（main 已存在的缺陷暴露）**：`_refresh_hud()` 末尾
   story/sim/else 链在 island 模式走 `else`，把 island 分支组装好的
   `model["selected_actor"]` 覆盖为 null。原版 island 选中为死代码所以从未显现。
   修复：else 兜底仅在 `island_sim == null` 时执行。演示模式行为不变（有专项回归）。
2. `p.beliefs[text]` 是 `{weight, source_event}` 字典，`float()` 直接转换会抛
   "Nonexistent 'float' constructor" 中断整个 `_refresh_hud` 协程。修复为取 `["weight"]`。
3. Camera2D 无 `clear_current()`（4.7 API），改为仅 `enabled=false`。
4. `:=` 从未类型化数组元素推断失败（`nx/nz`）——显式类型标注；`get_node` 需要
   NodePath 而非 StringName。
5. **首轮 strict regression 抓到两处集成问题（已修复后复跑）**：
   a. `run_all::hud_layout_in_view` 依赖工程视口 1280×720（遗留 main.tscn 玩家 HUD 布局），
      全局改视口会连累它——改为 observer/ui_preview 运行时设置 `content_scale_size=480×270`，
      工程视口还原 1280×720。
   b. `module_boundaries`：`scenes/ui/ui_capture.gd` 不得引用 `observer_main.tscn`（m15_ui
      无该依赖且会成环）——ui_capture 移入 `scenes/observer/` 并在
      `game/docs/architecture/modules.json` 登记为 m01 入口装配；全部新表现层文件
      （m13_presentation/m16_camera_input）同步登记。`node scripts/check-module-boundaries.mjs`
      复验 BOUNDARY_OK。

## 与模拟线的并行安全

- `game/src/simulation/**`、`game/src/runtime/**`、`game/config/**`、`scripts/**`、
  `.github/**`：0 文件改动。
- 共享文件改动仅 2 个：`game/project.godot`（display 渲染分辨率 480×270 / 窗口
  1920×1080 / nearest 过滤——headless 回归不受影响）与
  `game/scenes/observer/observer_main.gd`（谨慎允许范围：ViewModel 组装/2D 接线/选中）。
- `game/test/**` 0 改动：observer_sim 等 6 套件原样通过。

## 产品缺口（与单元测试成功分开陈述）

- 底部"故事/对话"页在真实运行早期常为占位（事件量随 tick 增长后填充）；因果链页依赖
  事件携带 `cause_seq`，当前 island 事件多数不带，链数少。
- Inspector 计划/历史页在 tick 早期数据稀疏（意图/记忆需要模拟推进）。
- items/ 图标管线已建但无 UI 消费点；世界物件会延伸到面板下方（已知限制见
  ui-architecture.md）。


## UI-R1 v2 迭代记录（同分支追加；v2 后完整回归 **PASS 42 套件 / 1269 断言 / 18 python 测试**，证据 .tmp/ui-r1-strict-evidence/）

1. **小地图 48×36**：observer_main 在 island build 时覆盖地图尺寸（config/生成器/模拟零
   改动；AIW_UI_MAP=full 退回）。四个 island 启动套件（island_sim/p0_cognition/
   p1_social/execution_receipt）在 48×36 下全绿后才定为默认。
2. **Inspector 7→6 页**：去 Plans；决策页加"下一步意图"；关系页加善意/可靠性/关系变化；
   历史页改三段（最近事件/最近对话/承诺请求行动链）；性格页三组（基础特质/气质与风险
   偏好/社交倾向）。plan_rows 字段随之退役（文档已更新）。
3. **Kenney Tiny Farm（CC0）混合地形**：11 种地面 tile 并入图集；识别用像素统计仲裁
   两次视觉核对（其中一次将水格 100/101 误判为树——统计仲裁否决）；树/围栏/树桩因
   双盲结果矛盾保守不采用，保留自制。原始文件与 License vendor 入库。
4. **整数倍放大**：`window/stretch/scale_mode=integer`；1366×768 下自动 letterbox。
5. 新增物件 19 种（小木屋/箱/桶/柜/横竖围栏/井/工作台/锯木台/幼苗/花/杂草/大石/
   木堆/石堆/作物两档/橡树/松树）+ farmland 地形帧；tree.png 由 tree_oak/tree_pine 取代。


## UI-R1 v3 返修记录（GPT 复审 UI_R1_VISUAL_REVIEW_NEEDS_FIX + DATA_PRESENTATION_NEEDS_FIX）

1. **Kenney tile 误识别撤回（阻断级）**：人工复审确认 tile_0011/0012（容器/物件）、
   tile_0100/0101（水槽/容器）、tile_0089（石堆）被误当地面/水。v3 撤回全部 11 帧
   Kenney 混合，地形图集恢复 100% 自制（生成器已去除混合层且不读取 vendored 文件）。
   全量 132 tile contact sheet（ID/原图/8×）随复审包提供，供后续逐 tile 人工批准。
   教训：禁止用像素统计/视觉模型投票猜第三方素材语义。
2. **关系页两层分离**：真实关系边（RelationshipStore：综合信任 + benevolence/
   reliability/obligation/fear 四维 get_dim）与主观心智模型（TheoryOfMind：有食/慷慨/
   可靠）分区展示，不再把 ToM 信念标成关系维度。
3. **布景阻挡纪律**：木屋/井/工作台/机器/围栏/箱柜/木石堆/营火/帐篷/市集/灯塔等
   阻挡语义物件一律不上可行走格——当前无可合法分配的 non-walkable footprint，
   全部取消（宁缺毋假）；可行走格只留花/杂草/幼苗/小作物等轻装饰；POI 改轻量木牌。
4. **游戏式 HUD**：未选中时 Inspector 收起；时间线默认收起为 tab 条（点 tab 展开、
   再点当前 tab 收回）；顶栏压缩为左世界名/日期时间 + 右倍速/暂停/⋯菜单（存档/
   基准/对照移入）。无选中状态世界占画面 ~89%（1920×1080 实测，目标 ≥80%）；
   1366×768 同布局（整数缩放 letterbox 内同比例，目标 ≥75%）。
5. **生成器入库**：generate_placeholders.py 之前被根 .gitignore 的 tools/ 模式
   静默忽略（v1 提交信息声称已提交是错的）——v3 以 git add -f 正式入库并验证
   确定性（连跑两次 md5 一致）；生成器不读取/不下载第三方素材。
6. **PopupMenu RID 泄漏修复**：顶栏菜单 PopupMenu 之前 new 后未 add_child，成为
   孤儿节点导致一轮 strict 回归以 "RID allocations leaked at exit" 判 FAIL——已入树。
7. **v3 后完整回归：PASS 42 套件 / 1269 断言 / 18 python 测试**（含泄漏修复验证，
   证据 .tmp/ui-r1-strict-evidence/）；9 fixtures、island/wander 启动、7 个定向
   套件（observer_sim/island_sim/execution_receipt/p0_cognition/p1_social/
   camera_rotation/run_all 共 278 断言）与 module_boundaries 全部复验通过。


## UI-R1 v3.1 Closeout 记录

1. **BottomPanel 真收起**：v3 的 visible=false 只藏内容页，面板仍占 74px（约 27% 画布）。
   v3.1 以 offset 动态切换：collapsed=16px（仅 tab 条）/ expanded=74px；无选中 + 收起时
   画布世界占比 ≈88.1%（顶栏 16 + tab 条 16 = 32/270 遮挡），满足 ≥80%。
2. **walkable 灌木移除**：bush/berry_bush 具视觉阻挡性，从草地散布分支删除
   （资产保留 RESERVED，待 non-walkable footprint）；walkable 仅 flower/weed/sapling/
   crop/shell/driftwood。
3. **Fresh Import + 全部截图重拍**：v3 截图被发现仍含已撤回的 Kenney tile——根因是
   regen 后未重新 --import，运行时渲染 .godot 缓存图集。v3.1 清理 import cache 后
   fresh import，从最终资源状态重拍全部 7 张（旧截图全部作废）。教训：**每次动生成器
   输出后必须 --import 再截图**。
4. ASSET_MANIFEST（tree.png→tree_oak/pine、RESERVED 标注、POI=poi_flag、Kenney 11 ID
   全量）、ui-architecture（Current/Planned 重写）、本文件（顶层 v3.1 + 历史折叠）同步。
5. **v3.1 后完整回归（已提交状态 2bb8bdc 上运行）：PASS 42 套件 / 1269 断言 / 18 python
   测试**；资产复验 48 张自制 PNG generated==committed 零失配（logs/asset-repro.txt）；
   world-clean 像素级来源自证（水体/草地主色=自制调色板，Kenney 灰蓝命中 0.01% 噪声级）。

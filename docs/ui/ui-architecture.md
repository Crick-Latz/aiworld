# UI-R1 架构说明（ui-architecture）

## 目标

把观察模式从 3D 视觉原型转向 2D 俯视像素原型：温暖、明亮、可读、轻量，
可替换资产体系 + 可扩展 ViewModel 结构。只动 presentation / scene / assets-prep /
inspector，不改模拟机制。

## 像素规格（明确选择）

- **tile size：16×16 逻辑像素**
- **内部渲染分辨率：480×270**（16:9；320×180 过挤，Inspector 7 页 + 中文文本放不下）
- **实现方式：运行时 `root.content_scale_size = 480×270`**（observer/ui_preview 场景自设；
  工程默认视口保持 1280×720——遗留 main.tscn 玩家原型与其 hud_layout 测试不受影响）
- **窗口：1920×1080 默认**（`window_width/height_override`），`--resolution 1366x768` 验证小窗
- **拉伸：canvas_items + keep**，全局面板纹理过滤 = Nearest
  （`rendering/textures/canvas_textures/default_texture_filter=0`）→ 1080p 下整数 4× 像素完美

## 场景结构

```
observer_main.tscn (Main, observer_main.gd)
├── World (Node3D, wander/story 演示模式专用，UI-R1 不动)
│   ├── Environment / Sun / GroundGrid / ObstacleGrid / PoiRoot
│   ├── NpcRoot (3D npc.tscn × 3)
│   ├── MapController (src/map，只读窄接口)
│   └── CameraRig/YawPivot/MainCamera (Camera3D)
├── World2D (Node2D, island 默认模式, UI-R1 新增)
│   ├── GroundTerrain (TileMapLayer, 运行时建 TileSet)
│   ├── PropsRoot (Node2D, 树/岩/POI 物件 Sprite2D)
│   ├── NpcRoot2D (Node2D, npc_2d.tscn × 3)
│   ├── SelectionMarkers/SelectionRing (Sprite2D)
│   └── Camera2D (ObserverCamera2D: WASD/方向键平移·滚轮缩放·右键拖拽)
└── ObserverHud (CanvasLayer → Root Control, observer_theme.tres)
    ├── TopBar（世界名/时间/状态/滞后/警告 + 暂停 1× 2× 4× 存档 基准 对照）
    ├── InspectorPanel（名字+状态 / 7 tab 网格 / 7 页内容）
    └── BottomPanel（事件 故事 对话 因果链 4 tab + 4 页）
```

双模式切换：`_enter_2d_mode()`（island：隐藏 World3D、投影地形、Camera2D 接管、
环境底色改暖色深水）/ `_enter_3d_mode()`（wander/story：全部还原）。
`AIW_MODE=wander|story` 仍走 3D 演示路径，测试依赖的
`World/MapController`、`World/NpcRoot`、`World/CameraRig/YawPivot/MainCamera` 节点路径不变。

## 数据流（ViewModel 隔离）

```
island_sim (模拟真值)
   │  只在 observer_main._refresh_hud()（presentation adapter）读取
   ▼
model: Dictionary（view_schema_version 0.2，见 OBSERVER_VIEW_MODEL.md）
   │  hud.render(model)
   ▼
ObserverHud（纯渲染：顶栏 / Inspector 7 页 / 时间线 4 页；占位文案兜底）
```

- HUD 组件不 import / get_node 任何模拟对象；缺字段渲染占位。
- 离线迭代走 `scenes/ui/ui_preview.tscn`（9 套 fixture，与正式 HUD 同一场景）。
- 截图工具 `scenes/observer/ui_capture.tscn`（preview/observer 两模式，`--` 后传参）。

## 2D 地形派生（纯表现层）

`World2DProjector.project()` 只读 MapController 窄接口
（`get_obstacle / is_walkable_tile / get_poi_tiles / get_spawn_tile / map_size`）：

- water：邻陆 → 浅水/泡沫边，否则深水
- tree → 林地底 + 树；rock → 岩地 + 岩石
- 可行走：邻水 → 沙滩；邻林 → 林地；哈希散布 dirt/bush/berry_bush/shell/driftwood
- POI → 帐篷/市集/灯塔占位；出生点 → 营火

装饰散布用稳定 FNV 哈希（非 RNG 流，不参与确定性回放诊断，纯视觉）。

## NPC 2D 表现（npc_2d.tscn + Npc2D）

- 接口与 3D npc_visual 对齐：`setup(id,name,color)` / `update_position(from,to,alpha,running)` /
  `set_selected(bool)` + `meta npc_id`
- 4 向 idle(2帧)/walk(4帧)/run(4帧)，占位 spritesheet 运行时切片为 SpriteFrames
- 面向由位移向量推导；`speed_multiplier>=4` 切 run 动画
- 名字标签世界空间渲染（缩放跟随相机），选中时白色高亮

## 交互

- 左键：距 NPC ≤18px 选中（空白点击取消）；选中环跟随
- Esc：暂停/恢复（island 模式 UI-R1 新接通；原版 island 模式 Esc 无效）
- 顶栏按钮 → 原 4 信号（pause/speed/save/scenario）不变
- Inspector/时间线 tab 手动选择后保持，首次渲染自动挑有内容的页

## 已知限制（R1 范围内接受）

1. 世界画面延伸到面板下方：NPC 走到地图边缘时名字标签可能被半透明面板压住（相机无
   面板避让）。正式版可用相机 limit 或面板布局调整。
2. 底部"因果链"页数据来自 `cause_seq` 派生，事件无 cause_seq 时显示占位。
3. wander/story 演示模式仍用旧 3D 表现 + 旧 HUD 字段子集（status_text 等新字段仅 island 组装）。
4. items/ 图标已入库但尚无 UI 消费点（物资图标面板属后续阶段）。

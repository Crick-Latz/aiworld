# UI-R1 像素资产清单（ASSET_MANIFEST）

## 素材策略（v2，项目确认非商用）

- **第一梯队（已并入）**：Kenney Tiny Farm（CC0，公有领域）——11 种高置信度地面 tile
  与自制帧混合进地形图集（grass_a/b、dirt、farmland、sand_a/b、shallow_a/b、foam_edge、
  deep_a/b）。选择依据：像素统计 + 双盲视觉核对一致；半透明区按主色展平。
  原始文件与许可 vendor 于 `game/assets/pixel/third_party/kenney_tiny_farm/`。
- **第二梯队（自制占位）**：其余全部自制——Kenney 包缺失（沙滩细节/林地底/悬崖/泡沫）
  或识别置信度不足（树/围栏/树桩，视觉核对两次结果矛盾时保守不采用）的帧。
- Sprout Lands / SunnyLand 未采用：本轮仅 Kenney 提供了可直接下载且许可为 CC0 的包；
  itch.io 系需浏览器会话下载，留待需要角色/高级物件素材时人工引入（引入前在本文件登记）。

### Kenney Tiny Farm（CC0）逐条登记

| asset | source | license | author | modified | where used |
|---|---|---|---|---|---|
| tile_0094/0106 | kenney.nl/assets/tiny-farm | CC0 1.0 | Kenney | 展平+入图集 | grass_a / grass_b |
| tile_0012/0011 | 同上 | CC0 1.0 | Kenney | 展平+入图集 | dirt / farmland |
| tile_0112/0113 | 同上 | CC0 1.0 | Kenney | 展平+入图集 | sand_a / sand_b |
| tile_0100/0101 | 同上 | CC0 1.0 | Kenney | 展平+入图集 | shallow_a/b、foam_edge |
| tile_0089 | 同上 | CC0 1.0 | Kenney | 展平+入图集 | deep_a/b |

**其余全部为自制占位像素图。** 所有 PNG 由
`game/assets/pixel/tools/generate_placeholders.py`（Python 3 + Pillow）确定性生成，
可随时重新生成或 1:1 替换为正式美术。调色板为暖色荒岛系（草地/沙滩/暖水/木色），
只借鉴"温暖清晰的农场/荒岛像素游戏"高层方向，不复刻任何现成游戏的素材与布局。

再生成方式：

```bash
python game/assets/pixel/tools/generate_placeholders.py
```

## 资产表

### tiles/（地形图集）

| 资产 | 尺寸 | 授权 | 作者 | 修改 | 使用处 |
|---|---|---|---|---|---|
| `tiles/terrain_16.png` | 128×48（8×3 张 16px 图块） | 项目自制（与仓库同授权） | UI-R1 生成脚本 | 否 | `PixelTileset` 运行时切图 → `World2D/GroundTerrain` |

图块清单（逻辑名 → 图集坐标）：grass_a/b、sand_a/b、dirt、path、forest_a/b、
shallow_a/b、deep_a/b、rock_ground_a/b、cliff_edge、gravel、foam_edge、sand_grass_edge。

### npc/

| 资产 | 尺寸 | 授权 | 作者 | 修改 | 使用处 |
|---|---|---|---|---|---|
| `npc/npc_sheet_16.png` | 64×192（4×12 帧，16px） | 项目自制 | UI-R1 生成脚本 | 否 | `Npc2D` 运行时切片为 12 组动画 |

帧表：行 0-3 idle×down/up/left/right（2 帧）；行 4-7 walk（4 帧）；行 8-11 run（4 帧）。
衬衫为近白色，运行时以 `modulate` 染角色识别色。

### props/（世界物件占位）

| 资产 | 尺寸 | 授权 | 作者 | 修改 | 使用处 |
|---|---|---|---|---|---|
| `props/tree.png` | 16×24 | 项目自制 | UI-R1 生成脚本 | 否 | 树障碍格 |
| `props/lighthouse.png` | 16×24 | 项目自制 | UI-R1 生成脚本 | 否 | old_lighthouse POI |
| `props/stump.png` | 16×16 | 项目自制 | UI-R1 生成脚本 | 否 | 预留（砍伐后树桩） |
| `props/rock.png` | 16×16 | 项目自制 | UI-R1 生成脚本 | 否 | 岩石障碍格 |
| `props/bush.png` | 16×16 | 项目自制 | UI-R1 生成脚本 | 否 | 草地散布装饰 |
| `props/berry_bush.png` | 16×16 | 项目自制 | UI-R1 生成脚本 | 否 | 草地散布装饰 |
| `props/campfire.png` | 16×16 | 项目自制 | UI-R1 生成脚本 | 否 | 出生点营火 |
| `props/tent.png` | 16×16 | 项目自制 | UI-R1 生成脚本 | 否 | post_house POI |
| `props/market_stall.png` | 16×16 | 项目自制 | UI-R1 生成脚本 | 否 | tide_market POI |
| `props/shell.png` | 16×16 | 项目自制 | UI-R1 生成脚本 | 否 | 沙滩散布装饰 |
| `props/driftwood.png` | 16×16 | 项目自制 | UI-R1 生成脚本 | 否 | 沙滩散布装饰 |

### items/（物资/工具图标，已建管线、尚无 UI 消费点）

`wood_log / stick / stone / shell / berries / fiber / fish / trap / axe / pickaxe /
hoe / watering_can / fishing_rod / campfire`——均为 16×16 项目自制，
命名与 `data/items` 物资线对齐，供后续物资面板/背包 UI 使用。

### markers/

| 资产 | 尺寸 | 授权 | 作者 | 修改 | 使用处 |
|---|---|---|---|---|---|
| `markers/selection_ring.png` | 16×16 | 项目自制 | UI-R1 生成脚本 | 否 | 选中角色脚下标记 |
| `markers/shadow.png` | 10×5 | 项目自制 | UI-R1 生成脚本 | 否 | NPC 脚下阴影 |

### ui/

| 资产 | 类型 | 授权 | 作者 | 修改 | 使用处 |
|---|---|---|---|---|---|
| `ui/observer_theme.tres` | Godot Theme | 项目自制 | UI-R1 | 否 | HUD 全局面板/按钮/字体样式 |

## 第三方素材

无。若未来引入 Kenney / SunnyLand / OpenGameArt 等 CC0 或明确可商用资源，
必须先在本文件登记（asset name / source url / license / author / modified / where used），
授权不清晰的图片禁止混入仓库。

Sprout Lands 特别条款备忘：free 版非商用，premium 版可商用——引入前必须核验版本与用途。

## 占位图与正式美术的替换约定

1:1 同名替换 `game/assets/pixel/**` 下的 PNG 即可，代码引用逻辑名
（`PixelTileset.TILES` / `World2DProjector.PROP_TEXTURES`），不需要改脚本。
建议正式美术保持 16×16 逻辑网格与"脚底对齐格底边"锚点约定。

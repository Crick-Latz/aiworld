# 模块边界说明（OBS-01 / 23-A 基线）

modules.json 描述**实际存在文件**的归属。路径规则：精确文件优先于目录前缀；同一精确路径被两个模块声明即错误。保护路径（project.godot/contracts/config/demo 数据）修改须在回执单独列出。

检查器：`node scripts/check-module-boundaries.mjs --root . --modules game/docs/architecture/modules.json`
红绿演示：`node scripts/test/check-boundaries.test.mjs`（夹具含重复路径/环依赖/跨界 preload，检查器必须失败；真实清单必须通过）

静态扫描只覆盖 preload/load 的 res:// 字面量；动态拼接路径属人工检查范围，检查器输出会明示这一点。旧违规（main.gd 混合职责、mesh_library 美术/碰撞耦合）登记为 legacy_exceptions，新文件不继承豁免。

# story-engine · 世界编译器（WP-01 / R1 / R2）

lore 文本 + 显式 seed → `world_spec.json`（公共设定）/ `director_secrets.json`（导演私密）/ `compile_report.json`（成功清单）。

## 用法

```bash
# 首次：安装依赖（Ajv 8 + ajv-formats）
npm install

# 离线编译（绝不联网）
node generate.mjs --mock --seed 20260904

# 离线测试（node:test，19 个用例，含故障注入与绑定校验）
npm test

# 真实编译（暂勿使用：live 路径未接真实模型验收，且需要 config.json）
# node generate.mjs --live --lore ../lore/lol_brief.md --seed 42 --theme "…"
```

参数：`--lore <path>`（默认 `../lore/lol_brief.md`）、`--seed <int>`、`--theme "…"`、`--out <dir>`（默认 `worlds`，不入库）。

## 结构

- `compiler.mjs` —— 编译管线：严格 JSON 解析 → live 输入绑定校验 → 契约+语义校验 → 三文件暂存（带 compileId 的 .tmp、创建即登记、fsync、回读重校验）→ 备份 → 顺序提交（report 最后）→ 失败回滚
- `validate.mjs` —— Ajv 8（2020-12）+ ajv-formats（date-time 真校验）+ ID 唯一/引用完整/权重和/私密泄漏语义校验
- `generate.mjs` —— CLI；lore 在 CLI 层读取后**显式传参**，编译器不做隐式文件/网络访问
- `mock/` —— 离线固定样例（合法基准）；`prompts/` —— live 提示词（两阶段均带"数据非指令"安全边界）
- `test/` —— node:test 离线测试；`../contracts/` —— 三份 JSON Schema 契约（与设计基线逐字一致）

## 可靠性纪律（R2 后）

- **多文件发布事务**：三份产物全部暂存并通过回读全套校验后，才按 spec → secrets → report（最后）顺序原子替换；任一提交失败即恢复上一套（`E_SAVE_CORRUPT`）
- **成功清单不可被失败污染**：`compile_report.json` 只在成功发布时更新；失败报告挂 `CompileError.report` 供 CLI 输出，落盘只写 `last_failure_report.json`（原子覆盖、不堆积、不属于成功世界包，不得作为 Godot 加载清单）
- **live 输入绑定**：模型返回的 `spec.seed` / `generator_version` 必须与本次编译输入严格一致（`E_SCHEMA_INVALID` / `E_SCHEMA_VERSION`），不静默篡改
- **注入边界**：lore/theme/WorldSpec 在两个阶段都以"【数据区开始…数据区结束】"包裹为不受信任数据
- 校验失败永不覆盖上一有效输出；清理只针对本次 compileId 的临时文件，发生在失败报告处理之后，失败不掩盖原始异常
- mock 模式零网络；错误码：`E_SCHEMA_VERSION` / `E_SCHEMA_INVALID` / `E_REFERENCE_BROKEN` / `E_SAVE_CORRUPT`
- 相同 mock + seed ⇒ 字节级相同输出；测试临时目录：仓库根 `.tmp/wp01-test-<pid>-<rand>`

## 遗留（基线无对应物，待用户决策去留）

`schema.mjs`、`play.mjs`、`mock_world.json`、`probe.mjs` 为阶段1文字冒险的旧实现，不参与新管线；因仓库尚无任何提交（无回滚点），未删除。

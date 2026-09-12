# P7.1B Runtime Wiring 最终验证报告

更新时间：2026-09-12。本文件记录 P7.1B（材料请求接入真实运行时）的最终本地验证证据，供合并 `main` 前复审。

## 1. Git

```text
base commit（origin/main） : b893b836950f8d8c4a1047a36722d08155ce08ab
validated source HEAD      : 68d3d6126ba56f2de597bedaf32a01628f17d8df
validation-infra fix       : e946950（本验证阶段新增，见 §8.3）
branch                     : work/p7-1-runtime-wiring
```

`68d3d61` 为 GPT 复审通过（`P7_1B_LIFECYCLE_FIX_APPROVED` / `READY_FOR_FINAL_VALIDATION`）的生命周期代码，本阶段未改动任何模拟逻辑。`origin/main` 在验证期间经 `git fetch` 核对无变化。

分支提交序列（自 origin/main）：

```text
75c131e feat(p7.1b): wire material requests into runtime blockers
b6421c3 test(p7.1b): cover live material request lifecycle
91afc94 fix(p7.1b): harden runtime request validity
eb38d4d fix(p7.1b): recover material request lifecycle after terminal outcomes
68d3d61 chore(godot): track P7 material request script uids
e946950 fix(validation-infra): register p7_1_runtime_wiring suite and material_request profile
```

## 2. Lifecycle（受控测试覆盖的生命周期行为）

以下行为全部由 `game/test/p7_1_runtime_wiring.gd`（72 断言）与既有 `p7_1_material_request`（90）、`p7_1_material_request_hardening`（14）以可失败断言锁定，并保存于定向测试日志：

- blocker → request：真实决策链（execution receipt 携带 `MATERIALS_MISSING` 等 blocker_reason）自动创建唯一请求；同一 blocker 不重复建请求。
- 主观选目标：仅从请求者可见（≤8 格）、ToM 持有证据信念 ≥0.08 且置信度 >0 的对象中选择；未知/不可见持有者不可选；不读全局真实库存。
- 接受 / 拒绝 / counter：应答只产生社会状态变化，接受本身不转移物品；counter 待请求者决断；部分数量进入 counter。
- counter 拒绝恢复：`reject_counter` 后请求回到 ACTIVE、`accepted_quantity` 清零、保留 history 中的被拒 counter 记录；被拒持有者从后续 offer 中排除，转向下一个主观候选。
- 过期恢复：TTL 到期置 EXPIRED；到期 tick 当拍转移仍合法、过期后转移失败且不改动库存；EXPIRED 在缺口仍在时以新 request_id 重建（`retry_of_request_id` / `retry_reason=REQUEST_EXPIRED`）。
- target missing 恢复：目标角色消失 → FAILED(TARGET_MISSING)，不改库存，缺口仍在时重建请求。
- giver inventory changed 恢复：应答后库存变化 → 转移失败 FAILED(GIVER_INVENTORY_CHANGED)，不伪造完成，重建请求。
- quantity stale 恢复：请求者已自行获得部分材料 → CANCELLED(REQUEST_QUANTITY_STALE)，按当前 authoritative gap 重建（数量随缺口缩小）。
- 终态重试白名单：仅 `REQUEST_EXPIRED / TARGET_MISSING / GIVER_INVENTORY_CHANGED / TRANSFER_FAILED / REQUEST_QUANTITY_STALE`（及部分转移 PARTIAL_TRANSFER 后续请求）可重建；`NO_LONGER_NEEDED` 不重建；run/plan/step 身份变化（PARENT_RUN_CHANGED / BLOCKER_CHANGED）不重建。
- 真实转移：只以双方权威库存执行，一次性变更；`ITEM_TRANSFER_COMPLETED` 携带 request_id；无关转移证据（request_id 不匹配）与重复转移证据都被 tracker 拒绝。
- 父计划身份保全：请求全程携带 `parent_plan_id / parent_run_id / blocker_step_id / blocker_reason / blocker_step_kind`，世界事件与追加式 trace 均保留该身份；成功转移授予一次性 revalidation token（四重身份校验：plan_id + run_id + step_id + state==BLOCKED），消费时要求重建提案中该计划 READY，否则 `PARENT_PLAN_REVALIDATION_REJECTED`；被替换计划不能凭旧转移复活；token 不存在时不发 PARENT_PLAN_REVALIDATION_REQUESTED 事件。

## 3. Audit（审计字段核对）

定向测试逐项断言（`_event_has_identity` / `_traces_have_identity` / history 检查）：

```text
parent_run_id            : CREATED/OFFERED/ACCEPTED/RESOLVED/EXPIRED/FAILED/CANCELLED 全部事件与 trace 携带
blocker_step_id          : 同上，且 run.current_step_id 变化即判 BLOCKER_CHANGED
blocker_reason           : 与 blocker_step_kind（CRAFT/ACQUIRE）分离记录，不互相覆盖
retry_of_request_id      : 所有重试请求指向旧 request_id（新 id 保证唯一）
previous_terminal_reason : 等于旧请求终态原因（REQUEST_EXPIRED 等）
```

## 4. Tests（定向测试实测结果）

命令：`tools/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script res://test/<suite>.gd`，日志保存于 `.tmp/p7_1b_final/targeted/<suite>.log`（stdout+stderr，含 SUMMARY 行，全部 exit 0、无 SCRIPT ERROR）。

```text
p7_1_runtime_wiring              72/72 PASS
p7_1_material_request            90/90 PASS
p7_1_material_request_hardening  14/14 PASS
framework_runtime                17/17 PASS
island_sim                        8/8  PASS
plan_adoption                    36/36 PASS
p7_information_subgoal           70/70 PASS
```

## 5. Strict Regression

- 第一次运行（`.tmp/p7_1b_final/strict/`，默认 --timeout 300）：`STRICT_REGRESSION FAIL`，唯一失败套件 `p3_narrative` exit 124（RUNNER_TIMEOUT）。诊断：该套件单独在本机重跑 **PASS 78/0，耗时 5m26s（326s）**，超过默认 300s 单套件上限；属本机（Windows）速度相对 CI Linux runner 慢的验证基础设施问题，非代码回归（P3 叙事层不在本分支改动路径上，CI 在 main 基线同一套件绿色）。
- 第二次运行（`.tmp/p7_1b_final/strict-r2/`，`--timeout 600`，套件清单含新注册的 `p7_1_runtime_wiring`）：

```text
STRICT_REGRESSION PASS   suites=39  assertions=1145  python_tests=18
p7_1_runtime_wiring      72/72（5.9s）
p3_narrative             78/78（323.6s，未再触及 600s 上限）
source_sha256 前后一致    source_unchanged=true
```

全部 39 套件 + engine_version / editor_import / module_boundaries / cognitive_import_python 四个门通过，无 SCRIPT ERROR、无失败套件。

失败证据（第一次）按规范保留未删除。

## 6. Deterministic Replay

命令均为 `python scripts/run-simulation.py --profile <p> --seed <s> --ticks 1000 --verify-replay --out .tmp/p7_1b_final/<file>.json`（Python 3.12.7 本机 Anaconda）。

```text
framework        seed 61000 : replay PASS  state_sha256=1003addf1eab39624d8f7f91…
information      seed 61003 : replay PASS  state_sha256=e072c02f5124543bf8d88bab…
material_request seed 61004 : replay PASS  state_sha256=2577bc9759b2d9677e444e58…
```

- framework / information 的 `material_request_counts` 为空、`material_request_rng_states` 为空：既有 profile 关闭材料请求，行为轨迹与基线兼容。
- 三者的 `material_request_sha256` 一致（= 空 trace 的 canonical 哈希），与 §7 的零触发结果互相印证。
- information 组 P7.0 能力保持：`information_counts {GOAL_CREATED:7, GOAL_RESOLVED:1, ATTEMPT_COMPLETED:3…}`。

## 7. Natural Experiment（material_request / seed 61004 / 1000 ticks，固定不换）

事件统计（自输出 JSON 的 material_request_trace 与世界事件）：

```text
request_created:        0
offer_sent:             0
accepted:               0
refused:                0
countered:              0
counter_accepted:       0
counter_rejected:       0
expired:                0
target_missing:         0
giver_inventory_changed:0
quantity_stale:         0
transfer_completed:     0
transfer_failed:        0
retries:                0
parent_revalidations:   0
acquire_completed:      0
craft_completed:        0
main_completed:         0
full_chain_completed:   0
```

原因归因（基于 plan_adoption_trace / plan_execution_trace 实测）：

- CRAFT 链计划持续被提出：`PLAN_HUNGER_set_trap` 作为候选出现 534 次、`PLAN_HUNGER_fish_food` 197 次；但主观采纳层 1331 次 DEFER，12 次 ADOPT 全部给了 `PLAN_HUNGER_berry_patch_food`（采浆果）。
- 全 run 12 个 run 无一进入 CRAFT/ACQUIRE 步骤（crafted=0、gathered_wood=0），`MATERIALS_MISSING` 类 execution receipt 从未产生，材料请求层的前置条件从未满足。
- 执行侧 `STEP_CANDIDATE_NOT_SELECTED` 137 次、run 终因 COMMITMENT_RECONSIDERED(5) / NO_PROGRESS_TIMEOUT(6) / OTHER_ACTION_CHOSEN(12) 结束。

结论：seed 61004 下材料请求生命周期零自然触发。机制正确性由 §2-§4 的定向测试与确定性重放证明；自然密度为零是 P7.0 已记录产品缺口（"完整 ACQUIRE→CRAFT→MAIN 链为零、计划采纳层不选 CRAFT 链"）的延续，不属于本阶段代码缺陷，亦未做任何 seed/资源/timeout/奖励调整来改变该结果。

不变式抽查（同 JSON）：无任何 MATERIAL_* / PARENT_* / ITEM_TRANSFER_COMPLETED 世界事件——与零请求一致，无伪造。

## 8. UID 与仓库卫生

### 8.1 UID 扫描（`.tmp/p7_1b_final/uid_scan.txt`）

```text
duplicate UID groups      = 0
tracked .gd 缺配对 .uid    = 0
磁盘存在但未跟踪 .uid      = 0
tracked uid 文件数         = 191（含 68d3d61 新跟踪的 P7 脚本 uid）
```

### 8.2 工作树

`git status --short` 干净；`git diff --check` 干净；`.tmp/`、Godot 缓存、引擎二进制均在忽略范围，无临时产物进入提交。

### 8.3 本阶段基础设施修复（e946950，6+/1-，无模拟逻辑改动）

1. `scripts/run-simulation.py` 的 `--profile` choices 缺 `material_request`（profiles.json 已有该 profile），导致指令要求的固定实验命令被 argparse 拒绝——补齐白名单。
2. `scripts/strict_suites.json` 未注册 `p7_1_runtime_wiring`（72 断言），strict regression 与 CI 永远不会执行它——按既有惯例（P7.1A 两套件与测试同 PR 注册）补注册，expected=72。

## 9. Product Gaps（如实保留）

1. **runtime reserve source 尚未建模**：`_material_recipient_context` 中 `reserve_quantity` 恒为 0，应答方不会为自身未来需求保留库存。
2. **自然运行零触发**（§7）：CRAFT 链计划被主观估值层持续 DEFER 是上游缺口；P7.2 前需评估"计划采纳估值是否系统性低估制作链"或"提高社会持有证据可达性"（后者为 P7.0 遗留）。
3. **首次 strict regression 的本机超时**：`p3_narrative` 在本机约 326s，超过默认 300s；CI Linux 不受影响。如后续本机复跑需带 `--timeout 600`。
4. `exchange_offer_value` 恒为 0（无回礼机制），counter 的 `requires_exchange=true` 分支目前只会被请求者以 `COUNTER_CONDITION_UNSUPPORTED` 拒绝——交换语义属 P7.2 范围。

## 10. 结论

P7.1B 的全部 correctness 门禁（定向测试、strict regression、三条确定性重放、UID/卫生检查）通过；自然实验零触发如实记录，不作为合并阻断。生命周期代码以 `68d3d61` 为准冻结，本阶段仅新增验证文档与两处验证基础设施修复。

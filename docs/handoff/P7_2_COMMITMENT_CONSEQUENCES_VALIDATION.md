# P7.2 Conditional Commitments & Autonomous Delegation 本地验证报告

更新时间：2026-09-12。本文件记录 P7.2 本地开发阶段的验证证据，供 GPT 复审。未 push、未建 PR、未改 main。

## 1. Git

```text
base HEAD（main） : 3839c72c6a907739c473a7c1dd7005e019f8d1de
final HEAD        : 本文件所属 docs 提交（代码末位 2211c2d；精确 SHA 见 Review Package manifest）
branch            : work/p7-2-commitment-consequences
commit_count      : 4
```

```text
2b27518 feat(p7.2): establish conditional commitment lifecycle（18 文件，+1188/−38）
05dd0f9 feat(p7.2): make commitments actionable and admit solvable material blockers（3 文件）
2211c2d test(p7.2): cover commitment consequence runtime chains（7 文件，注册 3 套件）
<docs 提交> docs(p7.2): record local validation（本文件 + 分析脚本；精确 SHA 见 manifest）
```

工作树 clean，git diff --check clean，无 CRLF 混入（提交内容逐一扫描确认）。

## 2. 架构

- **commitment authoritative ledger**：`IslandSimulation.obligations` 单台账（扩展记录，旧字段由 status 派生）。新模块 `game/src/simulation/commitment/`（contract/tracker/offer_policy/runtime_bridge 四文件）只操作该台账，无第二套状态，无缓存索引。
- **与旧 obligations 兼容**：旧记录原样保留并继续走 `_do_repay`/`_check_overdue_promises`；承诺型记录由 tracker 统一裁决（旧到期检查显式跳过带 `commitment_id` 的记录，避免双重违约）。`repaid`/`debtor`/`creditor`/`object` 由 status 派生。
- **feature flag**：`commitment_consequences` 默认 false；bootstrap 校验链 COMMITMENT_CONSEQUENCES_REQUIRE_MATERIAL_REQUESTS。
- **profile**：新增 `commitment`（LIVE_BRIDGE + 全链开关）；六旧 profile 全部补 `commitment_consequences: false`。同步了 simulation_profiles.json / run-simulation.py choices / bootstrap loader / framework_runtime 与三套新测试。

## 3. 承诺生命周期（定向测试锁定）

- **pending**：接受交换条款即建 `PENDING_ACTIVATION`，未获对价不成债（不计入 load）。
- **activation**：仅匹配的 `ITEM_TRANSFER_COMPLETED`（request_id + item 一致）→ ACTIVE；无关/重复转移被拒；激活单次。
- **fulfillment**：`_do_repay` 对承诺型债务走 bridge.settle——身份/状态/数量核验 → 唯一一次库存转移 → 证据 → FULFILLED；重复/库存不足拒绝且不改动库存。
- **violation**：到期仍 ACTIVE → VIOLATED（单次）；债权人消失 → CANCELLED(CREDITOR_GONE)（非违约）。
- **cancellation**：来源请求终局（转移失败/TARGET_MISSING/EXPIRED/stale）→ 未激活承诺取消（SOURCE_TRANSFER_FAILED / SOURCE_REQUEST_FAILED）；**激活后的债务独立于父计划**——父 run 消失/取消不抹债（测试锁定）。
- **terms mismatch**：A 愿意成交但自己的期限估计超出 B 要求（再获得性证据不足）→ COMMITMENT_TERMS_MISMATCH——不激活、不转移、不成债；认知上只做轻微确定性削弱（weaken 0.04），不施加违约级惩罚。B 的条款窗口随谨慎度收紧（240×(1.3−0.5×caution)），与 A 的主观期限估计（240×(1.3−0.6×再获得性)）构成自然分歧源。

## 4. 材料请求集成

- **exchange counter**：response policy 仅在上下文声明 `exchange_terms_enabled` 时附加条款（旧上下文输出逐位不变——hardening 套件锁定）。
- **requester decision**：`evaluate_requester_acceptance` 纯函数（紧迫度/互惠规范/在身负担/对 B 信任/主观再获得性/承诺数量比），确定性判断，可错性来自状态。
- **commitment offer valuation**：`estimate_promise_value`（B 的 ToM reliable 信念/关系/互惠规范/可见负担）与 `evaluate_commitment_offer`（条款级验证，单调性测试锁定：reliable↑→估值不降、覆盖率↑→不降、深度不信任→降低、负担↑→降低）。
- **transfer activation linkage**：P7.1B 转移成功路径挂 `activate_from_transfer`；所有请求终局路径挂 `cancel_for_request`。

## 5. 可行动义务与 §十六修复

- **问题类型**：root_goal=`OBLIGATION` 的 `PLAN_OBLIGATION_<commitment_id>` 计划由 ACTIVE 承诺生成，identity 含 commitment_id/creditor/object/quantity/due（due-window urgency 驱动 pressure）。
- **plan generation**：库存足量 → 单步 GIVE（repay_debt，绑定 commitment_id）；缺量 → ACQUIRE(gap)+GIVE——ACQUIRE 继续走既有 P7.0/P7.1 路径（第三角色入口）。
- **§十六诊断**（P7.1 零请求根因）：`means_ends_planner` 把任何 blocker 判 BLOCKED_PLAN → 采纳策略 PLAN_NOT_READY 拒绝估值 → CRAFT 计划永不采纳 → P7.1B 执行期钩子永不触发（61004 实测：set_trap 534 行/fish_food 197 行候选全部 PLAN_NOT_READY）。
- **修复**（仅 commitment profile，证据只来自角色自己的认知）：`_annotate_blocker_resolution` 按三种主观证据给可解 blocker 注解（已知来源 0.75 / ToM 持有信念 0.5+0.25b / 盲搜 0.35），进 cost+confidence 折减后参与估值；tracker 准入 resolvably-blocked 计划；SUBGOAL(find X) 在持有量达标后自动推进；SUBGOAL_INERT 在新 flag 下并入材料 blocker 触发白名单。
- **未做**：无 craft_bonus、无 seed 特判、无阈值放宽、无资源/timeout 改动。

## 6. 认知与关系

- FULFILLED → creditor 对 debtor reliability +120×positive_rate、benevolence +60×rate；VIOLATED → −250×betrayal_rate、−150×rate（复用既有互惠弧权重，role=recipient=债权人）。
- ToM：COMMITMENT_FULFILLED/VIOLATED 经 PROMISE 语义映射走既有 reliable 证据通道；TERMS_MISMATCH 仅 weaken("reliable", 0.04)。
- 事件 to_id=creditor（SubjectiveEvent role 映射锁定）；第三方知情仍受既有感知可见性约束，无全知广播。
- **后果回传决策环**（§十二）：同 roll 下 P_fulfilled > P0 > P_violated（B 端 context 由真实 CognitiveTransition 驱动后测量）；阈值翻转：违约历史→REFUSE、履约历史→ACCEPT（定向测试锁定）。
- **commitment_load**：来自台账真实 ACTIVE 承诺 + 旧未偿 obligations（同一口径）；终态出列。

## 7. 定向测试（日志 `.tmp/p7_2/targeted/`）

```text
p7_2_commitment              35/35   p7_1_runtime_wiring            72/72
p7_2_commitment_hardening    18/18   p7_1_material_request          90/90
p7_2_runtime_chain           34/34   p7_1_material_request_hardening 14/14
framework_runtime            17/17   island_sim                     8/8
plan_adoption                36/36   p7_information_subgoal         70/70
```

新增 87 断言；7 个 P7.1/P6 关键套件无回归。

## 8. Strict Regression

```text
STRICT_REGRESSION PASS
suites=42  assertions=1232  python_tests=18  source_unchanged=true
p3_narrative 78/78（266s，未触及 600s 上限）
```

第一次运行（`.tmp/p7_2/strict/`）FAIL：42 套件/1232 断言全过、python 18 过，唯一失败是 `source_unchanged=false`——回归运行期间执行者对本阶段文件做了 CRLF→LF 清理（Edit 工具写入带 CRLF，提交前 sed 修正），属验证执行期写保护误触发，非代码/测试问题。修正后换目录（strict-r2）重跑全绿；两份证据均保留。

## 9. 兼容性 Replay（同机 Windows，与开发前 baseline 逐位比对）

```text
framework        seed 61000 : replay PASS  state_sha256 与 baseline 完全一致
information      seed 61003 : replay PASS  state_sha256 与 baseline 完全一致
material_request seed 61004 : replay PASS  state_sha256 与 baseline 完全一致
```

比对键：state_sha256 / events_sha256 / execution_sha256 / adoption_sha256（BIT_COMPATIBLE）。未做 Windows↔Linux 跨平台哈希比较（RUNTIME-R1 已登记事项）。

## 10. P7.2 Deterministic Replay

```text
profile=commitment seed=61004 ticks=1000
replay_verified=true
state_sha256=429bf5b1a33fcea900163aab24b8489edee5e1fd08c9fb229ff01a0f2553a41e
commitment_rng_states={}（承诺层决策为确定性纯函数——零随机消耗即诊断证据）
```

## 11. 自然实验（10 固定 seed × material_request vs commitment，1000 ticks，未换 seed）

```text
                     material_request   commitment
requests created     0                  79
offers               0                  0
accepts/refusals     0/0                0/0
counters             0                  0
commitments created  0                  0
activated/fulfilled  0/0                0/0
violated/cancelled   0/0                0/0
terms mismatch       0                  0
transfers            0                  0
revalidations        0                  0
crafted（两 profile 一致） 4    fished 1    gathered_wood 423    gathered_shells 37
3+ actor chains      0                  0
ALL_REPLAY_VERIFIED=true（20/20）
```

**归因**：§十六修复生效——commitment profile 下材料请求从 0 → 79（CRAFT/SUBGOAL blocker 进入请求层），但全部止步于 `MATERIAL_REQUEST_NO_SUBJECTIVE_TARGET`（79/79）：请求者从未持有任何持有者的 ToM 证据。持有证据来自目击 gather/craft/transfer 事件（P7.1B possession observations），而自然运行中请求时刻请求者与持有者在感知范围内共现的频率为零。这是 P7.0 已登记产品缺口（"提高社会知识证据在自然运行中的可达性"）的同一堵墙，属上游信息环流问题，不是 P7.2 生命周期缺陷；按任务书 §二十一 不以放宽交互距离/信念阈值/资源的方式制造故事。两组 crafted/fished/gathered 完全一致，交叉验证了 commitment 层对非社会路径的零扰动。

**最终判定**：`MECHANISM_CORRECT` / `PRODUCT_ACCEPTANCE_NOT_YET_MET`——机制正确性由 87 断言 + 确定性重放 + 逐位兼容证明；自然 3-role 链为 0 的原因已定位到"持有证据环流"这一独立上游缺口。

## 12. UID 与卫生

```text
duplicate UID groups = 0
tracked .gd 缺配对 .uid = 0
磁盘存在但未跟踪 .uid = 0（新模块与测试的 uid 已随功能提交入库）
```

`.tmp/`、Godot 缓存、引擎二进制均在忽略范围；无临时产物进入提交。

## 13. 产品缺口（如实保留）

1. **持有证据环流**（本轮最大缺口）：自然运行中 possession 证据不在"请求者需要它的时刻"可达——候选方向：请求前的主动询问（"谁有 X"信息子目标，P7.0 询问机制扩展到持有谓词）、或共享记忆/传闻通道。均属后续机制，不在本阶段擅自添加。
2. runtime reserve source 未建模（reserve_quantity 恒 0，P7.1 遗留）。
3. exchange_offer_value 目前只反映 B 的静态信念；A 的履约历史经 CognitiveTransition 自然进入（测试已锁），但自然运行中尚无样本。
4. 阈值翻转测试的余量较窄（P0 与 P_violated 差距依赖学习率），后续可加显式回归锁定。
5. p3_narrative 本机 ~326s：本机跑 strict 需 `--timeout 600`（CI Linux 不受影响）。

## 14. 结论

P7.2 本地开发完成：单台账承诺生命周期、可行动义务、可解 blocker 准入、认知后果与决策环回传全部由可失败测试锁定；全量回归与三条兼容 replay 通过；自然实验如实记录零社会链与根因。等待 GPT 复审。

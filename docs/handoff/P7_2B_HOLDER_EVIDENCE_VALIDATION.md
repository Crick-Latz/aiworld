# P7.2B Holder Evidence Reachability 本地验证报告

更新时间：2026-09-13。本文件记录 P7.2B 本地开发阶段的验证证据，供 GPT 复审。未 push、未建 PR。

## 1. Git

```text
base HEAD（main） : d693a2f96a256b45efd6b042878988185d16f75b
final HEAD        : a9cd34e（docs 提交为最终位；精确 SHA 见 Review Package manifest）
branch            : work/p7-2b-holder-evidence-reachability
commit_count      : 3 + 本 docs 提交
```

```text
b81a4a4 feat(p7.2b): add subjective holder information goals
2d9bb01 feat(p7.2b): propagate holder reports with provenance and reenter requests
a9cd34e test(p7.2b): cover holder evidence reachability（+ analyzer）
<docs>   docs(p7.2b): record local validation（本文件）
```

## 2. 架构

- **feature flag**：`holder_evidence_reachability` 默认 false；bootstrap 校验链 HOLDER_EVIDENCE_REQUIRES_INFORMATION_AND_MATERIAL_REQUESTS。
- **profile**：新增 `holder_evidence`（全链：LIVE_BRIDGE + plan_execution + causal_step_value + plan_adoption + information_subgoals + material_requests + commitment_consequences + holder_evidence_reachability）；既有七 profile 全部 false。
- **information tracker extension**：InformationSubgoalTracker 扩展 FIND_HOLDER（query_kind=HOLDER，goal_id INFO:HOLDER:…，旧 SOURCE goal 形状不变——`goal.get("query_kind", "SOURCE")` 默认兼容）。并发纪律 A/B/C；多轮新 goal_id；唯一完成条件=同 request 的 MATERIAL_REQUEST_OFFERED；取消跟随 request 终局/run 漂移/step 漂移/gap 清零。
- **parallel holder tracker**：无。全部在既有 tracker + ToM + InformationActionPolicy + InformationExchangePolicy 内。

## 3. Holder 目标生命周期

- **creation**：request 处于 ACTIVE 且 try_offer 返回 NO_SUBJECTIVE_TARGET → prepare_holder（同 request 复用；同 plan+item 的 SOURCE goal 让位 MATERIAL_REQUEST_NEEDS_HOLDER；无关目标不覆盖）。
- **identity**：goal 携带 source_request_id + requester_id + item_id + parent_plan_id/run_id/blocker_step_id + holder_predicate。
- **supersession**：见并发纪律。
- **cancellation**：SOURCE_REQUEST_TERMINAL / PARENT_RUN_CHANGED / BLOCKER_CHANGED / GAP_CLOSED（每 tick `_holder_goals_sync_all` 复核；holder goal 不得复活父请求）。
- **multi-round**：目标 RESOLVED/CANCELLED 后同 request 再遇 NO_SUBJECTIVE_TARGET → 新 goal_id 的第二轮；同时至多一条 ACTIVE。
- **resolution**：仅同 source_request_id 的 MATERIAL_REQUEST_OFFERED 真实发生 → RESOLVED（ACTIONABLE_HOLDER_ACQUIRED）；远持有者报告只获得证据、目标保持 ACTIVE。

## 4. 询问策略

- **open inquiry**："我不知道谁有 X"本身是充分理由——无 MIN_PEER_KNOWLEDGE 预置信门槛；候选=others_visible 非自己、本轮未问过、不在 request 拒绝集（excluded_targets_for）。
- **candidate source**：A 自己的 trust_of / ToM reliable / sociability / conflict_avoidance / 距离 / request urgency 决定排序与 utility。
- **global truth access**：无——不读 B 真实库存/真实 ToM/全局"谁知道答案"。

## 5. 持有报告

- **self report**：B.inventory[item]>0 → HOLDER_SHARE（SELF_REPORT，confidence 1.0，observed=received=当前 tick）；意愿走既有 assess_willingness。
- **third-party report**：B 自己 ToM 的 subjects_with_evidence(has_item:X) 中信念>0 且新鲜（≤MAX_REPORT_AGE_TICKS=72）→ HOLDER_SHARE（TOM_REPORT，observed=C 原始证据 tick）；只有过期证据 → HOLDER_STALE；无可报 → 继续。
- **self absent**：B 自知不持有且无第三方可报 → HOLDER_SELF_ABSENT（负向 claim，目标不 RESOLVED）。
- **unknown**：无 tom / 无条目 → HOLDER_UNKNOWN。
- **refuse**：有可报但 roll>share_probability → HOLDER_REFUSE。

## 6. 证据来源（provenance）

- **predicate**：TheoryOfMind.possession_predicate(item)="has_item:<item>"（全工程唯一；P7.1 bridge 保留兼容 wrapper，输出不变）。
- **observed tick**：add_reported_evidence 存 observed_tick（事实年龄）；last_evidence_tick 返回 observed_tick。
- **received tick**：独立字段 + _models.last_updated 用 received_tick。
- **reporter**：evidence 携 reporter_id。
- **dedup**：同 event_id 重复处理返回 false（计数/置信度不二升）。
- **stale laundering protection**：请求侧重放攻击不可能——freshness 基于 observed_tick；hardening 测试锁定（tick 5 证据 + tick 100 询问 → HOLDER_STALE + observed_tick=5）。

## 7. Material Request 重入

- **same request ID**：证据获得后同 request_id / run / blocker_step 重建 holder beliefs → try_offer（测试锁定 request_id 前后一致）。
- **target acquisition**：holder 进入可见范围（≤8 格）+ belief≥MIN_HOLDER_BELIEF → OFFERED → 目标 RESOLVED。
- **refused target handling**：excluded_targets_for 跳过拒绝者；不重复 offer。
- **terminal request handling**：holder goal 跟随取消；不得阻止 expiry / 延长 TTL / 复活 PARENT_RUN_CHANGED。

## 8. 定向测试（日志 `.tmp/p7_2b/targeted/`）

```text
p7_2b_holder_evidence            27/27   p7_1_material_request        90/90
p7_2b_holder_evidence_hardening  19/19   p7_1_hardening               14/14
p7_2b_runtime_chain              26/26   p7_1_runtime_wiring          72/72
p7_information_subgoal           70/70   p7_2_commitment              43/43
plan_adoption                    36/36   p7_2_commitment_hardening    25/25
framework_runtime                17/17   p7_2_runtime_chain           56/56
island_sim                        8/8
```

13 套件全绿（新增 72 断言；10 旧关键套件零回归）。

## 9. Strict Regression

```text
STRICT_REGRESSION PASS   suites=45  assertions=1341  python_tests=18  source_unchanged=true
（一次通过——回归启动前所有源码已提交落盘，运行期间零文件操作）
```

## 10. 兼容性 Replay（同机，vs d693a2f 开发前 baseline）

```text
framework         61000 : LEGACY_BEHAVIOR_HASH_COMPATIBLE（state/events/exec/adopt/info/mr/commit 七哈希全一致）
information       61003 : LEGACY_BEHAVIOR_HASH_COMPATIBLE
material_request  61004 : LEGACY_BEHAVIOR_HASH_COMPATIBLE
commitment        61004 : LEGACY_BEHAVIOR_HASH_COMPATIBLE
```

## 11. Holder Evidence Replay

```text
profile=holder_evidence seed=61004 ticks=1000
replay_verified=true
state_sha256=440110c5c8151d42…（完整值见 manifest）
```

## 12. 自然实验（61000–61009 配对 commitment vs holder_evidence，1000 ticks）

```text
                       commitment   holder_evidence
requests_created       79           67
no_subjective_target   78           67
holder_goals_created   0            557
holder_goals_resolved  0            0
holder_goals_cancelled 0            49
holder_asks            0            4
holder_shared          0            0
  self_report          0            0
  third_party          0            0
holder_self_absent     0            4
holder_unknown         0            0
holder_refused         0            0
holder_stale           0            0
evidence_applied       0            4（全部负向 self-absent）
offered                0            0
commitments            0            0
full_chains            0            0
ALL_REPLAY_VERIFIED=true (20/20)
```

**机制验收**：受控三链全绿（自报解锁/三角色远持有者/拒绝二轮）——`MECHANISM_CORRECT`。

**产品验收**：`P7_2B_PRODUCT_ACCEPTANCE_NOT_MET`。新断点定位：
1. holder_goals=557 但 asks 仅 4——目标创建远多于询问。归因：prepare_holder 在每次 request ACTIVE 且 NO_SUBJECTIVE_TARGET 的 tick 都被调用（复用同 request 的 ACTIVE goal，不重复创建），但 557 创建说明请求-目标生命周期高频震荡（request 被 retry 机制重建 → 新 request_id → 新 goal）。这是 P7.1 请求重试白名单的既有行为，非新回归；但值得后续收敛目标churn。
2. 4 次询问全部 SELF_ABSENT（.tmp/p7_2b/holder-evidence-provenance-samples.json 4 条样本全为 npc_kadga 自报无贝壳）——被问者恰好不持有目标物品。零 HOLDER_SHARE、零第三方报告。
3. 根本断点：**三个 NPC 在请求时刻彼此邻近的概率极低**（各自探索分散），且被问者通常也不持有 wood/shells（这些是中间材料，被采集后立刻用于 craft 或囤积者远离）。持有证据机制已就绪但"可报告的持有事实"在自然运行中稀薄——下一瓶颈是社会共现密度（co-location）与中间材料分布，不是持有证据机制本身。

**P7.2 总体产品验收**：NOT YET MET（offers=0 → negotiation/commitment 链无法启动）。下一阶段方向（GPT 决策）：提高共现密度的机制化途径（如计划性会合/营地共存行为），或让中间材料持有更可见（craft 后剩余材料的事件可见性）。

## 13. UID 与卫生

```text
duplicate UID groups = 0
tracked .gd 缺配对 .uid = 0
磁盘存在但未跟踪 .uid = 0（新测试 uid 已入库）
```

## 14. 产品缺口（如实保留）

1. 自然询问密度低（4/20 runs 有询问，全部 SELF_ABSENT）：社会共现与中间材料分布问题。
2. holder goal churn（557 创建/49 取消）：请求重试与目标生命周期重叠导致——非错误，但审计噪声大。
3. P7.2A 两项非阻断（trailing whitespace、settle 可选参数）本轮未触碰。

---

# P7.2B-R1 Holder Lifecycle & Provenance Hardening（返修记录）

GPT 复审（R1 包，SHA256 c2ec996c…）：R1 core fixes PASS / formal review CHANGES_REQUIRED。
修复内容（提交 9b19745 / 0359248 / eb8bce3 / 9368097，均为机制分支纯净历史）：

1. **生命周期分发**：prepare() 按 query_kind 分发——ACTIVE HOLDER 原样返回，永不进入 SOURCE 的
   _candidate_still_present；终止权唯一归 resolve_holder_goal / cancel_holder_goal / _holder_goals_sync_all。
2. **询问记账**：on_action_complete 白名单 + ask_item_holder；attempts/asks/asked_actor_ids/refusals/
   stale/unknown 落账；同轮同人不重复询问、新轮新 goal_id 重新开始。
3. **极性新鲜度**：ToM latest_supporting_tick（方向感知；last_evidence_tick 语义不变）；
   evaluate_holder_query 正判断读正证据 tick——新鲜负证不能洗白旧正证（t5+t100→STALE observed=5）。
4. **HOLDER_UNKNOWN 决策（选项 A）**：协议预留态——完整库存自知下不可达，不为凑状态造分支。
5. **分析器前缀归属**：INFO:HOLDER: 前缀 + 通用 GOAL_* 终态每 goal 计一次。
6. **trace 形状兼容（9368097）**：身份字段只附 HOLDER 行，SOURCE 行逐字节不变。

修复效果（复审后 GPT 独立解析确认）：557→55 goals、PARENT_BLOCKER_REMOVED 507→0、
≤1tick 494→0、真实平均寿命 24.82 tick（GPT 校正了分析器把 per-run 平均相加的错误）、
asks 4→9、仍全 SELF_ABSENT。

---

# P7.2B-R1.1 收口（本轮）

GPT 对 R1 的三项收口要求（Git 分离 / 分析器聚合 / ATTEMPT_LIMIT 边界 + opportunity 漏斗），全部完成。

## A. Git 两线分离（勘察结论 + 证明）

- 勘察发现两线实际已被 UI 线自行分离：共享工作树当前检出 work/ui-r1-2d-pixel-observer
  （HEAD dbded60，三个 UI 提交直接基于 d693a2f），机制分支 work/p7-2b-holder-evidence-reachability
  仍纯净指向 9368097（无任何 UI 提交）。merge-base = d693a2f。
- R1 交接中 "df5b148 = docs(p7.2b-r1)" 的声明错误，根因：共享工作树双线并发提交竞态——
  UI 线曾把三个 UI 提交（4f893bc/8ab7f4f/df5b148）提交到机制分支之上，后被 UI 线重建到自己的
  分支；机制分支被指回 9368097；我的 docs 提交从未落地（验证文档 R1 节随本次重建）。
- 本轮起机制开发在独立 worktree（D:/Project_AI/aiworld_mech）进行，共享工作树完全留给 UI 线；
  stash@{0}（UI 线停泊快照）保留未动。旧 UI sha（4f893bc/8ab7f4f/df5b148）仍为可达对象，无丢失。

## B. 分析器聚合修复

- 寿命统计改为**原始样本池化后一次计算**（pooled_stats：count/avg/median/p90/min/max/le1/gt1），
  绝不再相加 per-run 平均值。
- unique asked 区分 global_unique_actor_ids（集合并集，主报告值）与 per_run_unique_sum。
- 新增 python 回归测试 tests/cognition/test_p7_2b_aggregation.py（6 测试）：[10,20]+[30]→avg 20 禁 45；
  {B,C}+{B}→global 2 禁 3；前缀归属；通用终态每 goal 计一次。runner python 期望 18→24。

## C. HOLDER ATTEMPT_LIMIT 生命周期边界

- on_action_complete 尾部分支：`elif query_kind != HOLDER and attempts >= MAX_ATTEMPTS` ——
  HOLDER 永不因通用上限进 FAILED（问尽后保持 ACTIVE 等待环境变化）；SOURCE 的 ATTEMPT_LIMIT +
  冷却语义逐位不变（单元测试直接锁定旧行为）。
- 新测试：10 次询问后 state==ACTIVE、同 goal_id、asked 保留；prepare_holder 同 request 复用同 goal；
  SOURCE 8 次 search 完成 → FAILED(ATTEMPT_LIMIT) 不变。

## D. Opportunity funnel 诊断（只观测，不改行为）

- IslandSimulation._holder_funnel_diag 纯加性计数器（只写不读），audit state 编码排除
  （fingerprint 不变测试锁定），数值仅经 summary.holder_funnel 输出。
- 计数点：sync（active_ticks）、决策（decision_ticks/visible/eligible/no_eligible/排除原因/候选数）、
  选中、启动、完成、missed、应答分类、应答者知识画像（自持/新鲜第三方/过期第三方）。

## 验证汇总（R1.1，全部在机制 worktree 执行）

```text
定向 13 套件全绿：46/27/26（P7.2B 三套，+9 新断言）+ 旧 10 套件零回归
python: 24 tests OK（18 旧 + 6 新聚合回归）
strict regression：见 manifest（一次通过，source_unchanged=true）
四 profile 兼容：LEGACY_BEHAVIOR_HASH_COMPATIBLE（vs d693a2f baseline 七类哈希）
  ——SOURCE ATTEMPT_LIMIT 行为与 SOURCE trace 形状均未变（专项断言锁定）
holder_evidence 61004 replay PASS
```

## 自然实验（重跑，20/20 replay verified）

HOLDER 生命周期（池化统计，与 GPT 独立解析逐位一致）：
```text
created 55 / terminal 55 / surviving 0 / resolved 0
cancel: PARENT_RUN_CHANGED=39  SOURCE_REQUEST_TERMINAL=16   PARENT_BLOCKER_REMOVED=0
lifetime: count=55 avg=24.8182 median=16 p90=48 min=2 max=48 le1=0 gt1=55
unique_asked: global_unique_actor_ids=[npc_kadga, npc_oun]（2）  per_run_unique_sum=3
```

Opportunity funnel（全 10 seed 累计）：
```text
holder_active_ticks            1365
holder_decision_ticks           650   （活跃目标参与决策的 tick）
holder_ticks_with_visible_peers 143   （22%）
holder_ticks_with_eligible_peers  79   （12%——可见且未问过且未被拒）
holder_ticks_with_no_eligible_peer 571 （88%）
peer 排除原因：already_asked=70  request_refused=0
holder_ask_candidates_emitted    82
holder_ask_actions_selected/started/completed  9/9/9   target_missed=0
应答：SELF_ABSENT=9（其余类别 0）
应答者画像：self_holder_at_query=0  fresh_third_party=0  stale_third_party=0
```

## 由数据得出的瓶颈结论

```text
B1 社会共现密度（询问率主限制）：650 个活跃决策 tick 中 88%（571）没有任何合格可问对象；
   仅 12% tick 存在合格同伴；候选出现时选择率 9/82（次级因素：信息行动竞争）。
B2 中间材料持有驻留（知识侧）：9 次真实询问时刻，应答者自持=0、新鲜第三方持有知识=0、
   过期第三方=0——被问者既不持有也毫不知情谁持有。
```

两个瓶颈同时成立且均由漏斗数据支撑：共现密度限制询问机会，材料驻留限制可报告知识。

```text
P7.2B-R1.1 mechanism correctness: PASS
P7.2B reachability acceptance: NOT YET MET
P7.2 overall product acceptance: NOT YET MET
next bottleneck: B1 社会共现密度（主）+ B2 中间材料持有驻留（次）——由 opportunity funnel 得出
```

## DEFERRED_FINDINGS

- P7.2A 两项遗留维持登记（p7_2_commitment.gd 六处行尾空格、settle() 身份参数改必填）。
- 选择率 9/82（信息行动与其他行动的 utility 竞争）留待 B1/B2 解决后复查是否仍显著。

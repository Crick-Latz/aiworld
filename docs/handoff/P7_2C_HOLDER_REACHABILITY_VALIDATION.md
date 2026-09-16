# P7.2C-0/C1/C2 Holder Reachability Ecology 本地验证报告

更新时间：2026-09-13。分支 work/p7-2c-holder-reachability-ecology（基于 5001bab）。未 push、未 PR。

## 1. Git

```text
base HEAD（main 基线之外的前置）：5001bab（P7.2B 机制收口，PR #9 已开待 CI）
final HEAD：见 manifest
branch：work/p7-2c-holder-reachability-ecology（mech worktree 开发）
```

## 2. 实现内容

### C-0 诊断（write-only；audit 排除 + fingerprint 等式测试锁定）

- **仲裁诊断**：ask 候选存在时记录 best utility / 选中行动 / 类别（7 类）/
  utility delta；win/loss 分开计数。类别映射为 const 字典（无分支开销）。
- **客观材料审计**：决策 tick 粒度统计真实世界持有者数/最近距离/可见/已知/未知——
  行为系统绝不读取（audit 层专用）。
- **材料驻留**：wood/shells 携带 actor-ticks + acquire/consume 事件计数。

### C1 Encounter Reachability（seek_holder_person）

- 触发条件：ACTIVE HOLDER goal + 无可见合格同伴 + holder_reachability flag 开。
- 目标选择：请求者自己的 ToM last_seen 记忆（trust/reliability/sociability/
  freshness/距离信念排序）——不读真实坐标/库存。
- 扑空是真实结果（stale last_seen → holder_seek_person_not_found）；
  到场产生 holder_seek_found_person，下一决策 tick 进入 others_visible → 询问自然发生。
- 执行走 _do_seek_holder_person（与 seek_person 同构：到场判定/事件记账/诊断）。

### C2 Inquiry Arbitration（询问效用语义）

- ask_item_holder utility 增加 parent_blockedness 项（BLOCKED run 驻留时长归一）。
- 公式：0.14 + max(pressure, urgency)*0.26 + blockedness*0.22 + trust*0.14 +
  reliable*0.10 + sociability*0.10 - conflict*0.06，clamp [0.06, 0.95]。
- 上限 0.95 不硬锁——极端生存行动（utility 可至 ~0.9+ urgency 加成）仍可压过。

### Profile/Flag

- 新 flag holder_reachability 默认 false；新 profile holder_reachability（全链九开）。
- bootstrap 依赖链 HOLDER_REACHABILITY_REQUIRES_HOLDER_EVIDENCE fail-closed。
- 旧 profile（含 holder_evidence）行为哈希逐位兼容（六组比对，见 §5）。

## 3. 定向测试

```text
p7_2b_holder_evidence            46/46（未变）
p7_2b_holder_evidence_hardening  40/40（+13 C-0 断言）
p7_2b_runtime_chain              38/38（+12 C1/C2 断言）
p7_information_subgoal 70  p7_1 三套 90/14/72  p7_2 三套 43/25/56
plan_adoption 36  framework_runtime 17  island_sim 8   —— 13 套件全绿
```

## 4. Strict Regression

```text
STRICT_REGRESSION PASS  suites=45  assertions=1393  python_tests=24  source_unchanged=true
（mech worktree 一次通过）
```

## 5. 兼容性（vs d693a2f baseline / R1.1 holder_evidence）

```text
framework 61000 / information 61003 / material_request 61004 / commitment 61004：
  LEGACY_BEHAVIOR_HASH_COMPATIBLE（七类哈希）
holder_evidence 61004 vs R1.1：HASH_COMPATIBLE（state 逐位一致）
holder_reachability 61004：replay PASS
```

## 6. 自然实验（10-seed 配对 holder_evidence vs holder_reachability，20/20 replay verified）

```text
                     control(holder_evidence)  treatment(holder_reachability)
holder goals         63                        69
asks                 13                        15
offers               0                         0
```

### Treatment 侧完整漏斗（新诊断）

```text
decision ticks       804
visible ticks        312（38.8%）
eligible ticks       187（23.3% of decision）
no eligible ticks    617（76.7%）
candidates emitted   272
selected/won         15（5.5% of candidates）
lost                 257（输给 EXPLORATION 179 / SOCIAL 64 / SURVIVAL 6 / OTHER 8）
loss delta avg       0.096（胜者 utility 平均只高出 0.096）
win utility avg      0.514
seek selected        5（completed 5 / found 2 / missed 3）
```

### 客观材料审计（C-0B，首次数据）

```text
objective_any_holder_ticks    111/804（13.8%）
objective_no_holder_ticks     693/804（86.2%）
nearest holder avg distance   61.4 格
actual holder visible         0/111
actual holder known(last_seen) 0/111
actual holder unknown          111/111
carriage wood                 7965 actor-ticks（436 次采集，~18.3 tick/次驻留）
carriage shells               3853 actor-ticks（30 次采集，~128.4 tick/次）
```

## 7. 瓶颈判定（由本轮新数据支撑）

```text
C3 Material Retention Bottleneck：CONFIRMED（主）
  86.2% 决策 tick 世界里没有任何真实持有者；wood 采集后平均 18.3 tick 即被消耗。
  即使 13.8% 有持有者的时刻，请求者也 0/111 知道（无 last_seen 记忆），
  且无一在可见范围内（0/111 visible）。

C1 Encounter Reachability：CONFIRMED（次）
  最近持有者平均距离 61.4 格（interaction range 8）；
  76.7% 决策 tick 无可见合格同伴；seek 已实现但 5 次中 3 次扑空（stale last_seen）。

C2 Inquiry Arbitration：改善但仍有限
  C2 修复后询问胜率从 9/82(11%) 提升到 15/272(5.5%)？——否：分母不同。
  对照组 9 selected / 82 candidates = 11.0%；治疗组 15/272 = 5.5%。
  胜率下降因为候选更多（blockedness 提高了 ask utility 使更多 tick 进入候选态）
  而胜者 delta 平均只有 0.096——竞争仍激烈。EXPLORATION 是主要胜者（179/257）。
  询问竞争力已改善（win utility avg 0.514），但探索行动的 utility 仍系统性更高。
```

**P7.2C 第一阶段产品目标评估**：
- C1 opportunity 增加 ✓（eligible ticks 79→187，+137%）
- C2 询问不再长期被压制 △（胜选从 9 升至 15，但占比未升；EXPLORATION 主导）
- 自然 HOLDER_SHARE ✗（15 次询问全部 SELF_ABSENT——与 C3 一致：86% 时刻无人持有）
- **明确证明世界客观上几乎没有 holder** ✓（objective audit：86.2% no-holder）

## 8. 最终判定

```text
P7.2C-0/C1/C2 mechanism correctness: PASS
P7.2C reachability acceptance: NOT YET MET（offers 0 / shared 0）
P7.2 overall product acceptance: NOT YET MET
next bottleneck: C3 材料驻留（CONFIRMED：86.2% 无持有 + 18.3tick 驻留 + 0 知情）
  → 下一步应正式设计材料保留机制（craft 后盈余/囤积倾向）
  C2 残余问题：EXPLORATION 179 次压制——需在 C3 解决后复查
```

## 9. DEFERRED_FINDINGS

- P7.2A 两项遗留维持登记。
- seek 5 次中 3 次扑空：stale last_seen 的真实代价——数据不足判定是否需要
  "找人失败后换目标/更新记忆"机制（样本仅 5）。
- EXPLORATION 作为主要仲裁胜者：其 utility 结构（好奇心驱动）与信息行动的
  语义重叠值得 C3 之后复查——探索本身也是一种信息获取。

---

# P7.2C-R1 Seek Bookkeeping & Diagnostic Integrity（返修记录）

GPT Round 1 复审：C-0/C1/C2 均 CHANGES_REQUIRED（三个 blocker）。全部修复（d5307fc / 3a15cc7）。
PR #9（P7.2B）已按独立授权正常合并（merge commit 84cab8e）。

## 修复内容

### B1：seek bookkeeping 分流
- on_action_complete 按 match 分流：seek_holder_person 写 seeks/sought_actor_ids
  （_dynamic_list 动态创建——flag-off 的旧 goal shape 逐位不变），不碰 asks/asked_actor_ids。
- _build_seek_holder 排除 self/asked/excluded/**sought**（stale 扑空后换人找）。
- 找到的人进 sought 不进 asked——下一决策 tick 可正常 ask。

### B2：诊断漏斗 ask/seek 分离
- 诊断层按 action 字段过滤：ask_item_holder → ask funnel；seek_holder_person → seek funnel。
- 独立 probe（kind 字段）；seek 胜不进 ask loss、ask 胜不进 seek loss。
- 不变量测试锁定：eligible peer → 只产 ask；无 eligible + last_seen → 只产 seek；
  ask_candidate_ticks <= eligible_ticks。

### B3：真实 material residence episode tracker
- carriage tick 驱动：0→正记 episode 起点；正→0 闭合记时长（sum/count/min/max）。
- SimulationAudit.fingerprint() 调用 _censor_open_residence_episodes() 导出时闭合残留
  （censored 标记，不假装消费完）。
- post-craft surplus 在 _do_craft 真实结算点记录（per consumed item）。
- objective audit 拆分 per-item（any/no_holder_<item>_ticks、distance_sum/count_<item>、
  visible_actual_holder_<item>），改名 actual_holder_position_known，新增
  actual_holder_positive_possession_belief（ToM belief > threshold）。

## 修正后自然实验漏斗（同 10 seed，20/20 replay verified）

### CORRECTED ask funnel（此前 272 candidate 中 85 实为 seek）


### CORRECTED seek funnel（独立）


### 真实 residence duration


### item-specific objective audit


## 修正后瓶颈判定



## P7.2B PR #9 merge 后状态



## 验证


---

# P7.2C-R2 / R2-R1 / R2-R1.1 / R2-R1.2 系列记录（本轮收口）

## R2（31f5c01/5b01240）：C3b possession observation + C2 causal arbitration
## R2-R1（a1623ca/28481cf）：spatial→visual-only、candidate-local boost、initial stock
## R2-R1.1（fd8eb7b）：visual/audible_close 拆分、polarity-aware freshness、distributed audit
## R2-R1.2（本轮）：test integrity + 客观归因诊断收口

GPT R2-R1.1 复审遗留两项 + 本轮自查一项，全部修复：

1. **C2 dead test**：`_test_r2r11_c2_real_arbitration` 已定义未接线（R1.1 抓过
   的同类问题）。已接入 `_run()`，并改为真实 ActionRegistry 双候选竞争
   （rest u=1.0 极端能量赤字 vs blocked ask；普通 explore vs blocked ask，
   支配性比较），不再只验 clamp 上界。
2. **K4 polarity regression dead test**：`_test_r2r12_k4_polarity_regression`
   定义后未接线（本轮自查发现——strict2 通过 70/70 时该测试根本没跑）。
   已接线：旧正证据 tick5 + 新负证据 tick100 → 综合 belief 仍 >0.05、
   正向 freshness 取 tick5（非 100）、mixed 口径 last_evidence_tick=100。
   hardening 70→73 断言，strict_suites.json 同步 1423→1426。
3. **distributed knowledge 命名过强**：`knowledge_exists_elsewhere` 实测
   "任何人对任何 peer 有正向信念"（不指向真实持有者）。拆分：
   - `network_has_any_positive_holder_belief_ticks`（general）
   - `network_knows_actual_holder_ticks`（objective 归因：读真实 inventory）
   - `visible/last_seen_knowledge_carrier_knows_actual_holder_ticks`
     （知情携带者是否可及——relay 可操作性）
   - requester 侧同理：`requester_belief_points_at_actual_holder_ticks`
     （"有正向信念"已由 holder_ticks_with_any_positive_possession_belief
     覆盖，不重复计）

## R2-R1.2 性能事件（记录，非代码回归）

strict2/strict4 p3_narrative 600s 超时。诊断：全部无关套件中位 3.36× 均匀
减速（story_causal 1.8→6.5s 等），p6_3_items 出现 38722s（机器休眠 10.7h，
45/45 断言通过后 exit 124）。结论：机器瞬时限速 + 休眠污染，非代码。
另修复 R1.1 遗留的 _emit 无条件 can_see（flag-off 恢复短路求值，
visual 仅在 possession 观测开启时精确判定；flag-off 无消费者）。
strict5 以 --timeout 1200 重跑：**PASS 45/1426/27，source_unchanged=true**，
p3_narrative 243.6s（回到历史区间）。

## R2-R1.2 兼容性（compat2，六组 FINGERPRINT-IDENTICAL）

framework/information/material_request/commitment vs d693a2f：逐位一致
（七类哈希 + RNG 状态）。holder_evidence/holder_reachability vs R1.1：
逐位一致。40 个 natural2 run 与 R1.1 natural 同 seed 全部指纹一致——
R1.2 零行为改动，新诊断键为同轨迹附加读取。

## R2-R1.2 知识源覆盖（新客观归因键，10 seed 池化）

```text
arm            decision  requester真值信念  network知情  知情者可见/last_seen
reach            804       0 (0.0%)          0           —
possess          804       0 (0.0%)          7 (0.9%)    0 / 0
arbitr           624       0 (0.0%)          0           —
ecolog           624       0 (0.0%)          7 (1.1%)    0 / 0
objective any-holder: reach/possess 111/804(13.8%)  arbitr/ecolog 111/624(17.8%)
```

**判定（供下一轮方向决策）**：
- requester 在决策 tick 从未持有指向真实持有者的信念（0/2212 全臂合计）。
- C3b 观测让网络"有人知道真持有者"仅 7 tick（0.9-1.1%），且这 7 tick 里
  知情者对请求者不可见、无 last_seen 记忆——**relay 机制无接触通道**。
- 结论与 R1.1 一致并被客观归因加固：**下一轮 = encounter ecology
  （提升物理共处/观测机会），不是 social relay**。
- 附带观察：C2 仲裁臂 decision ticks 804→624、goals 69→55——仲裁抑制了
  边际 goal 创建/维持，机制正确方向（省预算）但压缩了信息行动机会数。

## 验证

```text
strict5:  STRICT_REGRESSION PASS suites=45 assertions=1426 python_tests=27
compat2:  ALL_SIX_COMPATIBLE（vs d693a2f / R1.1 逐位）
natural2: 40/40 replay verified，指纹与 R1.1 natural 一致
hardening: 73/73（+3 r2r12 K4 polarity；r2r11 为真实双候选竞争）
```

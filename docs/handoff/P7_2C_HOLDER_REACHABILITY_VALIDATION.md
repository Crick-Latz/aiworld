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

---

# P7.2C-R2-R1.3 Visual Knowledge Source Coverage（纯诊断轮，零行为修改）

GPT R1.2 复审 PASS 后授权：区分"NPC 在 request 前很少视觉碰见真 holder"（原因 A）
与"碰见了但 event-gated observation 没写入"（原因 B）。本轮禁一切行为修改。

## 实现（全部 diagnostic-only，audit 排除，行为零读取）

- **A 决策 tick 视觉覆盖**：actual_holder_exists / visual_to_requester /
  visual_to_any_peer / visual_to_any_nonholder_peer——严格
  SpatialPerception.can_see（视野+LOS），禁 distance<=3/spatial/audible。
- **B encounter episode 去重**：observer×holder×item，false→true 转换记
  episode start（持续看见同一 episode）；per shells/wood；carriage 同款
  tick 扫描（感知后、行动前采样；_emit 观察在事件时刻——窗口归属分类，
  顺序无关）。
- **C 观察转化**：episode 闭合时按"窗口内是否有 K1 visual possession 观察"
  分类 with/without + conversion rate；episode 外观察单独计数
  （tick 内采样时点差的 gap 证据）。不主动写 evidence，只观察现有机制。
- **D pre-request 回溯**：HOLDER goal 新建时（created_tick==tick 区分复用），
  按 actor+item 键控历史 ∩ 当前真实持有者集——曾看过后来消费掉材料的
  actor 不计入。4 个布尔计数（requester/any × saw/observation）。
- **I 顺手修**：r2r11 场景 1 的 ordinary explore 从硬编码 0.35 改为正式
  ActionRegistry 候选（普通需求 actor，_pick_unvisited 确定性），断言
  blocked ask > 真实 explore 候选 utility。
- 新 probe/history 4 个状态变量加 simulation_audit _encode 排除；
  fingerprint() 导出时 censored 闭合开放 episode（residence 同纪律）。
- hardening +12 r1r3 断言 +1 explore 生成断言：73→86；strict_suites 1426→1439。

## 验证

```text
strict6:  STRICT_REGRESSION PASS 45/1439/27  source_unchanged=true
          （--timeout 1200 = LOCAL VALIDATION OPERATIONAL OVERRIDE，
           断言门槛/manifest 未变；p3_narrative 正常区间）
compat3:  六组 FINGERPRINT-IDENTICAL（4 legacy vs d693a2f + 2 holder vs R1.1）
natural3: 40/40 replay verified，events+state 与 R1.2 natural2 逐 seed 全一致
          → 本轮零行为改动再次成立
hardening: 86/86（defs=calls=21 全接线）
```

## E 知识源漏斗（10 seed 池化）

```text
                                reach   possess  arbitr   ecolog
decision ticks                   804      804      624      624
actual holder exists             111(13.8%) 111   111(17.8%) 111
holder visual to REQUESTER         0        0        0        0
holder visual to any peer          6        6        6        6
encounter actor-ticks           4599     4599     4833     4833
encounter episodes (sh/wood)   252(106/146) 252  314(106/208) 314
unique observer-holder pairs      19       19       24       24
K1 obs writes                      0     1498        0     1382
episodes with obs                  0      173        0      200
episodes without obs             252       79      314      114
conversion rate                    -    68.7%       -    63.7%
obs outside episode                0       38        0       47
pre-request creations             69       69       55       55
pre-req requester saw holder       0        0        0        0
pre-req any actor saw holder       1        1        1        1
pre-req requester observation      0        0        0        0
network knows actual               0        7        0        7
carrier visible / last_seen        0/0    0/0       0/0     0/0
```

## F 方向判定数据（按 GPT R1.3 §F 规则）

- **requester 视觉覆盖极低**：0/111 决策 tick、0/69 pre-request——
  视觉 encounter 存在（252）但观察者几乎从不是未来 requester。
- **observation conversion 高**：68.7%/63.7%（possess/ecology）——
  event-gating 不是瓶颈，排除原因 B（无需 Perception-Driven 修复）。
- **network knowledge 不明显**：7/804（0.9%）——relay 仍无授权条件。

**结论：原因 A（requester 层面）成立 → 下一阶段正式 Encounter Ecology**
（共同地点/会合/营地共处/主观 last_seen 找人；仍禁真实 holder 神谕定位）。

## H 仲裁压缩归一化表（SIDE EFFECT UNDER OBSERVATION，未修）

```text
                        reach/possess      arbitr/ecolog
goals / material req        1.00               1.00
decision ticks / goal       11.7               11.3
eligible ticks / goal        3.0                1.6   ← 仲裁轨迹使可见同伴减半
ask win on eligible        7.8%              11.6%   ← 条件胜率升（R1.2 已见）
terminal: HOLDER GOAL RESOLVED=0（全臂）；CANCELLED:PARENT_RUN_CHANGED ~71%
material request lifetime   ~26.9 ticks（n=68/55） ← 知识使用窗口本身很窄
```
压缩来源=goals 69→55（非 decision/goal 下降）；主导终止原因是父计划变更。
附加信号：即使知识存在，~27 tick 的 request 生命周期也是硬窗口。

---

# P7.2C Round 3 Encounter Ecology（E1 社会回流 + E2 锚点 fallback）

GPT R1.3 direction gate PASS 后授权的首个行为轮。设计约束：request 生命周期
~27 tick + PARENT_RUN_CHANGED ~71% → 主方案必须是 PRE-request 社会共现。

## 实现

- **flag `holder_encounter_ecology`**（默认 false；bootstrap 依赖
  holder_reachability fail-closed：ENCOUNTER_ECOLOGY_REQUIRES_HOLDER_REACHABILITY；
  LIVE_BRIDGE 要求清单同步）。新 profile：holder_encounter（C3b ON/C2 OFF/E ON）、
  holder_full_ecology（全 ON）→ 与既有 profile 构成 2×2（C3b 固定 ON）。
- **E1 `visit_social_anchor`**（ActionRegistry，flag 经 actor view 注入——
  flag-off 时键不存在，候选表逐位不变）：sociability + social 需求积累
  （=距上次有意义接触时间代理）驱动回访自己【见过】的火堆（主观
  known_resources，key "x,y"，fail-closed）。dist 4-40 才生成；utility
  (0.12+soc*0.22+social*0.30)*dp，夜×0.85/暴风×0.7/fear>0.5×0.6；≤0.64 档
  （critical survival ~0.9 自然压制）。到场发 social_anchor_visited 事件
  （目击者经 _emit 路径刷新 last_seen + possession 观察）。
- **E2 `seek_social_anchor`**（InformationActionPolicy）：HOLDER goal +
  无 visible eligible + 无任何 last_seen 目标（seek_holder 也空）时，去最近
  主观火堆（dist≤30）。utility 0.10+pressure*0.22+soc*0.10（fallback 档）。
  到场有伴 → social_anchor_arrived（下一 tick others_visible 驱动 ask）；
  没人 → social_anchor_empty（自然失败）。非 goal 终态。
- **诊断加固（R1.3 遗留缺口）**：encounter scanner 每 tick 构建有效 pair 集，
  扫描后对集合外的开放 episode 立即自然闭合（holder 耗尽/actor 消失也触发）
  ——duration 不再跨越 non-holder gap，不等 fingerprint censor。
  outside 键改名 event_time_observation_outside_preaction_episode_<item>
  （时点差语义澄清：事件时刻观察 vs 行动前 episode 采样）。
- 新诊断键（write-only）：E1/E2 selected/completed/arrived/missed +
  holder_seek_social_candidates_emitted。
- 行为零真值：E1/E2 只读 known_resources（主观）+ ToM/人格/需求；执行层
  到场裁决与其他 seek 同构（执行证据层合法）。

## 测试

- hardening 86→91（episode lifecycle：sweep 自然闭合/重获新 episode/
  duration 不跨 gap/真实 holder 耗尽下一 tick 闭合）。
- runtime chain 38→60：+13 Round3（flag 默认关/两新 profile 依赖链/E1 候选
  与效用档位/fail-closed 三态/E2 目标=主观火堆/距离上限）+9 **R1 遗留 dead
  test 接线**（_test_r1_found_then_ask_full_chain / _test_r1_real_arbitration_
  semantics 定义后从未被调用——Round3 自查发现，接线后全过）。
- strict_suites 1439→1466。

## DEFERRED_FINDINGS（本轮登记，未修）

- **`_sit_by_fire` 解析缺陷（预存，main 行为线）**：known_resources["fires"]
  键格式为 "x,y"，但 _sit_by_fire 按 "(x, y)" split(", ") 解析 → 永远解析
  失败返回 null。20 个自然 run（1000 tick×10 seed×2 臂）中 fire_lit=166 而
  sat_by_fire=0——"营地=社交心脏"机制从未生效。修复会改变所有旧行为 profile
  的轨迹，需单独授权；E1/E2 用正确解析（"x,y"），不依赖该函数。

## 验证（strict8 / compat / ablation 于计数器缩进修复后的最终源码）

```text
strict8:   STRICT_REGRESSION PASS 45/1466/27  source_unchanged=true
           （--timeout 1200 = LOCAL VALIDATION OPERATIONAL OVERRIDE，门槛未变）
compat:    九 profile FINGERPRINT-IDENTICAL
           framework/information/material_request/commitment vs d693a2f
           holder_evidence/holder_reachability vs R1.3
           holder_possession/arbitration/ecology vs R1.3 natural（61004）
ablation:  5 臂 × 10 seed 全 replay verified；旧臂与 R1.3 natural 同 seed
           轨迹一致（flag-off 零行为改动的再次证明）
hardening: 91/91   runtime_chain: 60/60（defs=calls 全接线）
```

## Round3 消融漏斗（10 seed 池化；enc=holder_encounter，full=holder_full_ecology）

```text
                                reach  possess ecol(C2)  enc(E)  full(E+C2)
decision ticks                   804     804      624     537      529
goals                             69      69      55      54       53
holder exists ticks               111     111     111      88       88
holder visual to REQUESTER          0       0       0       0        0
holder visual to any peer           6       6       6      29       29
encounter episodes (sh+wd)        302     302     370     272      272
K1 observation writes               0    1498    1382    1209     1209
episodes with observation           0     203     236     200      200
pre-req requester saw holder        0       0       0       0        0
pre-req ANY actor saw holder        1       1       1       9        9
requester any-belief ticks          0       0       0       0        0
network knows actual                0       7       7      88       88
carrier visible / last_seen       0/0     0/0     0/0     0/0      0/0
E1 visits selected/completed        -       -       -    26/26    26/26
E2 seeks selected/completed         -       -       -     2/2      2/2
E2 arrived with peer / missed       -       -       -     1/1      1/1
ask selected                       16      16      10       9        6
seek_person selected                 5       5       5       3        2
seek found                           2       2       4       3        2
HOLDER RESOLVED / OFFERED          0/0     0/0     0/0     0/0      0/0
request lifetime (同 R1.3 口径)   26.9    26.9    25.9    23.2     23.2
```

## Round3 判读（诚实陈述，两段式）

**机制生效（自然非零信号 ✓）**：E1 26 次营地回访全部完成；E2 2 次锚点
seek（1 次到场有伴=自然机会、1 次扑空=自然失败保留）。网络层知识大幅改善：
decision tick 网络知情 7→88（12.6×）、pre-request 任一 actor 见过当前持有者
1→9（9×）、holder 对任一 peer 可见 6→29（~5×）。

** requester 侧接触通道仍未打开（诚实限制）**：holder visual to REQUESTER
仍 0/88；requester any-belief 仍 0；知识携带者对 requester 可见/last_seen
仍 0/0。E1 制造的网络知识停留在"别人知道"，requester 与知情者/持有者在
决策 tick 仍未共位。ask_known_target=0、RESOLVED=0、OFFERED=0——产品链
未闭合。

结构性原因（推断，供下轮决策）：
1. E1 是个体短访（duration 2、utility ≤0.64、~2.6 次/seed/1000tick）；
   3 个 actor 同时在营地的联合概率仍低。
2. sit_by_fire 死码（DEFERRED）意味着没有"停留/聚集"机制——到营地的人
   下一 tick 就被 explore 拉走。
3. E 臂 decision ticks 804→537/goals 69→54：轨迹变化压缩了机会数
   （与 C2 压缩同向；SIDE EFFECT UNDER OBSERVATION 延续）。

## 验证补记

- 计数器缩进事故：E1/E2 selected 计数初版被误嵌进 ask if 块（seek 计数
  一并失活）。strict7+59 run 后发现同轨迹下 holder_seek_actions_selected
  从 1 变 0 → 修复缩进 → strict8 + compat/ablation 全部重跑（本节数据
  均来自修复后源码）。

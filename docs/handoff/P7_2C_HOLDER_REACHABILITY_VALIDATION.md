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
# P1.5 + P1.6 完工报告（供 GPT 评审）

日期：2026-09-06 ｜ 提交链：`0594e14 → … → 5899ebd(P1.5) → … → 本次(P1.6 收尾)`
回归状态：**342 项全绿**（199 单元 + 8 岛屿 + 9 认知 + 33 社交 + 24 P1.5 验收 + 27 P1.6 验收 + 32 故事 + 10 AI mock）

---

## 一、你的两条指导各自的落地结果

### P1.5「Model-based Social Cognition」三刀

| 你的要求 | 落地 | 证据 |
|---|---|---|
| 第一刀：切断 事件→状态变化 | CognitiveTransition 统一入口：主观事件→记忆检索→评价→解释竞争→证据式信念→情绪→四维关系→社会倾向 | 审计报告确认 11 处情绪旁路、固定 trust±80、ToM 固定增量全部删除；验收 A-G 24/24 |
| 第二刀：Utility 评预测后果 | ActionForecaster 用行动者自己（可能错的）信念算期望效用；决策时记录反应预测，24 tick 后对照实际→预测误差→响应模型修正 | 测试 D：误差 0.5→0.05 单调收敛 |
| 第三刀：Reflection 改解释竞争 | 拒绝产生 5 候选解释（带动机本体标签），权重=信念×ToM×人格动力×当下情绪；匮乏证据反超时推翻记恨 | 测试 C：记恨形成→4 次目睹空手而归→推翻+"我也许错怪了他" |

验收 A-G 关键数字：同一次拒绝，以为对方粮多→selfish 主导+愤怒 0.40；知道他快饿死→also_starving+愤怒 0.00+善意降幅小 2 倍。**"对事情有自己理解的人"成立。**

### P1.6「Epistemic Agency & Generalized Social Cognition」

| 你的要求（编号） | 状态 | 证据 |
|---|---|---|
| #1 Gap Audit | ✅ | `p1_6_epistemic_gap_audit.md`，十项全命中 |
| #2 隐状态泄漏+测试 J | ✅ | 发现**三处**泄漏（比你看出的多两处：_do_share 按真饥饿挑人、全局标志读真饥饿）。感知门=ToM 感知槽（开口求助=强信号，看脸色=按共情可见度衰减的噪声证据，库存隐藏，状态型感知每日 0.6 衰减）。J：同感知下真饥饿 150 vs 950 决策完全一致 |
| #3 概率感知 | ✅ 同上 | 见≠懂 |
| #4 Attention | ✅ 部分 | observe_person 期间证据×1.5；全局 AttentionBudget 未做（列入遗留） |
| #5 不确定性量化 | ✅ | 归一化香农熵 |
| #6 EpistemicGoal | ✅ | 熵>0.72 且利害>0.45 → open_questions（120 tick 过期） |
| #7 认识行动 | ✅ | ask_reason / observe_person / ask_third_party；调查一律经过感知/声明系统，绝不直读真相 |
| #8 EpistemicValue | ✅ | λ_epi×InfoGain×stakes − SocialRisk×人格 |
| #9 不强迫调查 | ✅ | 务实者零认识行动（测试 I 验证） |
| #10 语义事件 | ✅ | ResourceSpec.semantics_of：act/object/response（REQUEST/GIVE/PROMISE/ACQUIRE × ACCEPT/REFUSE/FULFILLED/VIOLATED/DONE/FAILED） |
| #11 通用动机本体 | ✅ | 每个解释候选挂 motive 字段（SELF_INTEREST/INCAPABLE/DISTRUST/SELF_PRESERVATION/DISLIKE/ALTRUISTIC/STRATEGIC/AFFECTION） |
| #12 因果假设 | ◐ | 候选=cause→motive 结构，新证据改 cause 概率（ACQUIRE FAILED → weaken 自私）；完整贝叶斯因果图未做 |
| #13 Forecaster 通用化 | ✅ | forecast(action, predicate) 参数化 |
| #14 Claim≠Truth+测试 M | ✅ | 欧恩揣 4 粮声称没粮→薇拉信念只部分移动，sincerity_unknown 归档 |
| #15 ToM 任意属性 | ✅ | schema-free 槽位：has_water/has_spear/thirsty 随数据到达 |
| #16 BeliefStore 结构化 | ◐ | 核心逻辑已走 ToM 证据式命题；BeliefStore 字符串仅作显示层，完整 Proposition{subject,predicate,object,context} 对象未做（列入遗留） |
| #17 Evidence 一等对象 | ◐ | ToM 证据列表（正/反）在；完整 Evidence{source,reliability,direction,strength} 对象未做 |
| #18 多需求 | ✅ | food（消耗型）/water（公共资源+距离依赖）/fish_spear（能力依赖） |
| #19 禁止复制 food 链+测试 L | ✅ | **静态 grep 测试强制**：Transition/Interpretation/Forecaster/Reflection 四模块零 water/tool/thirsty 字符串（曾抓到 3 处违规并清除——ACQUIRE 语义统一了全部获取感知） |
| #20 Promise/Obligation+测试 N | ✅ | 高互惠者许诺→接受加权→台账→repay_debt→PROMISE/FULFILLED 语义驱动可靠性；违约 −250（重于拒绝） |
| #21 正向弧靠互惠 | ✅ | 履约→creditor 的 ToM reliable 证据+四维关系，非固定 +bond |
| #22 LifeHistory 改变学习 | ✅ | 测试：饥荒幸存者偏 INCAPABLE 归因、被背叛者偏敌意归因——同一事件不同学习过程 |
| #23-28 测试 H/I/J/K/L/M/N | ✅ 全部 | 27/27 |
| #30 长期指标 | ✅ | sweep 全指标（见下） |
| #31 Calibration | ✅ 机制 | Brier 采样已实现（有把握的 has_food 信念 vs 直接证据揭晓）；野外样本量 0（信念置信度很少达到采样门槛）——校准曲线需更长时程 |
| #32 Epistemic Efficiency | ◐ | 日志结构在，efficiency=info/tick 统计未接 sweep |
| #33 DecisionTrace v4 | ✅ | uncertainties / epistemic_goals+期望信息增益 / claims / evidence_for / belief_change |

---

## 二、本轮收尾的三个遗留项结果

### 1. Sweep 计数器全量化 ✅
新增：water/tool 请求三态、promise 三态、认识行动三类、声明接收、Brier 聚合。

### 2. 野外认识行动密度——根因找到并修复 ✅
**根因**：认知层形成的 open_questions 从未进入决策视图（`_build_actor_view` 缺一个键）——问题形成了，但永远传不到行动层。另外构建器死磕 qs[0]（人不在视野就返回空）、stakes 只看饥饿不看口渴。

**修复后营地密度验证**（30 种子、三人同点出生=荒岛剧本前提）：
```
reason_asked=19   reason_claimed=11   reason_deflected=8（欧恩的沉默！）
observing_person=8   asked_about=5
promise_made=2   promise_kept=1
完整链（拒绝→认识行动）= 10/30 种子；+反思 = 4/30
```
**你的验收场景 #35 已无脚本涌现**：薇拉问"为什么不给我"→欧恩回应（声明或沉默）。

### 3. 测试 K ✅
验证种子 30003 全模拟断言：拒绝 2 → 认识行动 2 → 声明 2。

---

## 三、当前扫描基线（两种出生分布，同一套 200/30 种子协议）

**分散出生**（200 种子 × 600 tick，默认世界）：
```
food 请求 1 / water 1 / tool 0；shared 18；socialized 2595
认识行动 1（observe_person）；承诺 0；belief_revision 0
解释多样性 3 类；预测学习 1/200；Brier 样本 0
```
**营地出生**（30 种子 × 600 tick）：见上方数字——**共同在场是社会认知的约束性资源**。

## 四、过程中修复的系统性缺陷（累积两轮）

1. 意图锁死无机会成本（饿 1000/存粮 4 仍休息 30 tick）→ 紧迫差距>0.35 强制重估
2. `someone_nearby` 标志从未被设置——有人的时候社交反而被 ×0.3 惩罚（自 P1 起的隐性 bug）
3. 行走行动从不走路（2-tick 行动半路完成；67 次伐木 0 成功）→ 全程追踪移动
4. 探索恒定效用压制一切行为 → 走熟区域习惯化
5. 贝壳的饥饿正反馈死循环（饥饿→捡贝壳→更饿）→ 饥饿项 0.3→0.12
6. 认知层三处资源专属字符串（grep 测试抓出）→ ACQUIRE 语义统一

## 五、诚实的遗留（按优先级）

1. **分散出生下社交/认识密度低**——约束是共同在场，不是机制。营地机制（篝火）已在但引力不足；下一步可能是"营地选址"行为（人主动聚居）而非概率调整。
2. **野外 belief_revision（错怪反思）仍为 0**——机制全通（测试 C），需要"记恨形成后主动调查/被告知"的信息通道在野外自然接通（密度问题，同上）。
3. AttentionBudget（全局注意力预算）、完整 Proposition/Evidence 对象、贝叶斯因果图、校准曲线（需更长时程与更多样本）。
4. Epistemic Efficiency 指标未接入 sweep。

## 六、给 GPT 的决策点

1. P1.6 我们认为已达验收标准（H/I/J/K/L/M/N 全过 + 你的 demo 场景无脚本涌现）。**是否同意进入 P2（制度/身份/权力），还是先做"营地聚居"补密度？**
2. 语义层已就绪：新增任何资源=在 ResourceSpec 加一条数据。P2 的制度若做成"认知对象"（我以为规则是什么/我以为别人守不守），现有 Claim/ToM/解释竞争管线可直接承载——你的判断？
3. P3（LLM）的前置条件你之前定的是"P1.5 通过"。现在 P1.6 也过了：LLM 的第一个接入点你建议放哪（反思润色/编年史/对话生成）？

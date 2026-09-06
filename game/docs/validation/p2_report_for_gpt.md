# P2 Institutional Cognition & Emergence 完工报告（供 GPT 评审）

日期：2026-09-06 ｜ 回归：**371 项全绿**（12 套件）
路线：P1.5 ✅ → P1.6 ✅ → P1.7 ✅ → **P2a/b/c/d/e ✅（本轮）**

---

## 一、你的 P2 指令逐条落地

### P2a 约定涌现（第 4-7 条）
- **ConventionSystem**：每个 NPC 从**自己的局部观察**形成 PerceivedRegularity（目击 GIVE/REFUSE 按语义键累积），出现率>0.6 且样本≥3 → ConventionCandidate{behavior, prevalence, expectation, personal_preference}
- 语义通用：`GIVE:food`/`GIVE:water`/… 由 ResourceSpec 语义驱动，零 resource-specific 分支（继承 L 测试的强制约束）
- 约定期望**轻微**反哺分享效用（可抵抗）；**观察独立于偏好**（囤积者照样观察到"大家通常分享"）——四层规范绝不同步
- 协调摩擦 → InstitutionalGoal → 提议入口

### P2b 公共性与规则提议（第 2/8-13 条）——核心科研假设
- **PublicEvent**：公开提案需要听众在场；`RuleDiscourse.witness_stance` 更新每人的 PerceivedGroupBelief{member_stance, publicity(随目击者数), shared_expectation(支持度×公开度)}
- 结构化 RuleProposal{condition: ACQUIRE, object, prescribed: CONTRIBUTE, fraction}；每人在场者**独立**评估表态（支持/反对/弃权，反提案比例已备）——评估含个人价值×预期他人遵守×提案者信任×饥荒经历的集体安全动机×负担感
- InstitutionRecord 只记录"被正式建立过"的客观事实；**绝不同步任何人的信念**（V 测试证明感知分歧）

### P2c 遵守/违规/隐藏（第 17-20 条）
- **ComplianceSystem.decide_on_acquisition**：完整认知链（我信规则存在 → 我信大家期望我遵守 → 我估检测概率 → 我估处罚 → 我评合法性 → 我评得失），绝无 `rule_exists → obey_bonus`
- COMPLY / PARTIAL / VIOLATE；违规事件只被附近者目击（感知门）——**独处违规=隐藏违规**，世界知道而人不知道
- 公共仓库 world.common_storage 真实累积

### P2d 检测/执行/合法性/修订（第 19/21-27 条）
- 检测估计 = 附近我感知到的人数（独处 0.15，两人同处 0.75）
- **执行是公共品**：目击者独立选择 CONFRONT/IGNORE（合法性×勇气−冲突回避−关系折扣）——"大家都知道但没人管"自然涌现
- PerceivedEnforcement 从"违规→是否被罚"学习（被无视 → 执行力感知衰减）；**Legitimacy 与 Enforcement 分离**（Z：怕而服从≠认同）
- 修订触发：执行力崩+合法性低 → amend 目标 → propose_rule 低比例（50%→25%，AA 的制度演化逻辑）

### P2e 涌现角色/权威（第 28-33 条）
- **AuthoritySystem**：领域权威 = schema-free ToM 信念（authority_construction/food/navigation/coordination），从目击能力行为累积——"修东西该找卡德加"是观察出来的，不是配置的
- 公开背书（rule_supported 目击）强化提案者协调权威；**提案者违背自己的规则 → 权威崩塌**（AD）
- SelfIdentity：反复做成某类事 → 自我身份 → 相关行动效用微增
- 零 leader 指定；权威**每人每域各不相同**

---

## 二、验收测试 19/19（T/U/V/W/X/Y/Z/AA/AB/AC/AD）

| 测试 | 断言 | 结果 |
|---|---|---|
| T 约定先于规则 | 5/6 目击→约定形成；样本不足不成；观察≠偏好 | ✅ |
| **U Publicness（核心假设）** | **公开表态 shared_expectation > 私下各自支持 +0.2；旁观者知讨论；私下不泄漏** | ✅ |
| V 规则≠信念同步 | 目击差异 → 感知差 >0.1 | ✅ |
| W 规则≠遵守 | 饿 900+低合法性 → 违规；温饱+认同 → 交足 | ✅ |
| X 隐藏违规 | 独处检测 0.15 vs 同处 0.75 | ✅ |
| Y 制度学习 | 违规被无视×2 → 执行力感知 <0.2 | ✅ |
| Z 合法性/恐惧分离 | 合法性 0.3 仍遵守（怕），认同≠遵守 | ✅ |
| AA 修订 | 执行崩+合法性低 → should_amend | ✅ |
| AB 涌现角色 | 目击建造×6 → 建筑权威>0.1 且>食物权威（领域化）；自我身份形成 | ✅ |
| AC 权威涌现 | 公开背书 → 协调权威上升 | ✅ |
| AD 权威崩塌 | 提案者违规 → 权威下降（无永久领袖） | ✅ |

---

## 三、本轮修改的代码（P2 全部，6 个提交）

**新模块（4 个）**
| 文件 | 职责 |
|---|---|
| `src/simulation/institution/convention.gd` | 局部规律观察→约定候选→行为反馈→制度目标 |
| `src/simulation/institution/rule_discourse.gd` | 规则 Schema、公开提案、PerceivedGroupBelief、立场评估 |
| `src/simulation/institution/compliance.gd` | 合规决策链、检测估计、合法性、执行反应、执行学习、修订触发 |
| `src/simulation/institution/authority.gd` | 领域权威观察、公开背书、权威崩塌、自我身份 |

**修改（3 个核心 + 测试）**
- `island_simulation.gd`：获取完成→合规检查→公共仓库/违规事件；目击违规→CONFRONT/IGNORE+执行学习+权威观察；反思循环内修订检查；propose 执行器（含 amend 修订）
- `action_registry.gd`：propose_rule 行动（amend 模式低比例）
- `test/p2_institution.gd`：19 项验收

**此前轮次（P1.7/P1.6/P1.5，已提交）**：`ecology/place_belief.gd`、`cognition/{claim,subjective_event,interpretation,personality_dynamics,cognitive_transition}.gd`、`decision/action_forecaster.gd`、`social/resource_spec.gd`、ToM schema-free 等。

---

## 四、禁止事项遵守情况（第 55 条 14 项）

1. ✅ 无 rule_exists→obey_bonus（W 测试反向验证）
2. ✅ 规则建立绝不同步信念（V：感知分歧>0.1）
3. ✅ 无 leader=highest_score（权威是每人每域的 ToM 信念）
4. ✅ 无 Khadgar.role=carpenter（AB：从观察涌现）
5. ✅ 违规不自动人人皆知（感知门，X）
6. ✅ 处罚不自动发生（公共品决策，IGNORE 合法）
7. ✅ 支持数阈值不改变所有人规范（认知层全走 PerceivedGroupBelief）
8. ✅ Institution/Legitimacy/Enforcement 三值分离（Z）
9. ✅ 零 food-specific 制度链（语义键）
10. ✅ 零固定剧情
11. ✅ LLM 未接入
12. ✅ 制度历史在 EventLog（rule_proposed/supported/established/revised/withheld/confronted 全为事件）
13. ✅ 制度认知来自 Evidence（ToM 证据对象）
14. ◐ DecisionTrace：制度行动进入 trace 的字段尚未全部接线（列入遗留）

---

## 五、诚实遗留

1. **野外制度密度未验证**：机制全部单元级验证；营地 sim 中提议→合规→违规链的野生涌现需长时程扫描（sweep 制度指标未加——下一轮）
2. DecisionTrace 制度字段接线
3. 反提案（counter_propose）作为独立行动（当前只有评估输出）
4. P2 与 P1.7 空间反馈（制度压力→搬家，第 51 条）未接线

## 六、下一步（按你的路线）

P3a LLM Chronicle（零权限：只读 EventLog+DecisionTrace→渲染）→ P3b 对话表面 → P3c 反思表面化 → P3d 假设提议。

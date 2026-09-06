# P1.5 认知差距审计（2026-09-06）

结论先行：GPT 的判断成立。当前系统在**术语层**是认知架构，在**因果层**仍是
`事件 → 固定数值变化` 的规则系统。六个审计项全部命中，逐项证据如下。

## 1. Event 是否直接修改关系？ → **命中：DIRECT_EVENT_EFFECT**

- `island_simulation.gd:404/412`：`_do_request` 在行动完成处直接调用
  `relationships.on_help_accepted / on_help_declined`。
- `relationship_store.gd:8-9`：`TRUST_REJECT_PENALTY := -80`、`TRUST_HELP_REWARD := 100`
  ——常量硬编码，与解释、情境、人格全部无关。
- 后果：无论薇拉"以为欧恩粮多"还是"知道他快饿死"，拒绝一刀切 -80。
  事件从未经过"欧恩为什么拒绝"的解释环节就改了关系。

## 2. Reflection 是否只是事件计数器？ → **命中**

- `reflection_system.gd:42`：`if refused_by >= 2 → 生成"靠不住"信念`。
- 拒绝次数是唯一输入；没有候选解释、没有权重、没有新证据修正通道。
- 一旦记恨生成，没有任何机制能推翻它（发现"他当时真的没粮"不会降低记恨）。

## 3. ToM 是否只是几个固定字段？ → **命中（部分使用，无预测-纠错环）**

- `theory_of_mind.gd:37-49`：`has_food/generous/reliable` 三字段，按事件类型
  固定增量（foraged +0.35、refused generous −0.35……）。
- 有被消费：`pick_request_target` 读 `has_food`、`evaluate_food_request` 读 `reliable`
  ——所以它不只是存储，但它是 **social feature store**，不是预测模型：
  没有任何"预测他人反应 → 观察 → 预测误差 → 修正"的环节。
- 欧恩从未预测过"薇拉被拒后会怎样"，也就从未因预测错误而更新对薇拉的认知。

## 4. Emotion 是否由事件直接增加？ → **命中（双轨并存）**

- 旁路 11 处：`island_simulation.gd` 的 `_do_forage/_do_fish/_do_explore/_do_share/
  _do_socialize/_do_ruins/_update_weather` 直接 `adjust_emotion("joy"/"fear"/"sadness", 固定值)`。
- 正规轨道只有 `_appraise_and_react`（AppraisalSystem），且 AppraisalVector 与
  角色认知几乎无关——`food_request_refused` 只看 proposer_id 是否是自己 + norms 标量，
  不看"她以为欧恩有多少粮"（这是解释层缺失的连锁后果）。

## 5. Norm 是否单一标量？ → **命中（三种含义混一体）**

- `island_simulation.gd:153`：`norms = {sharing, self_reliance, reciprocity}` 单层。
- `sharing` 同时被当作：我该分享（personal，用于 SocialSystem 接受权重）、
  我以为别人会分享（descriptive，被拒时漂移 −0.03 ——`island_simulation.gd:414`）、
  社会谴责自私（injunctive，无）。
- `island_simulation.gd:414` 违反规则十六：被拒直接拉低"我认为该分享"，
  把"现实是什么"和"我认为应该是什么"混为一谈。

## 6. DecisionEngine 是否评分"动作本身"？ → **命中**

- `action_registry.gd` 全部 14 个行动构建器：`score = f(当前需求, 人格特质, 距离)`
  ——评价的是"我现在多想做"，从未预测"做了会发生什么"。
- `evaluate_food_request`（欧恩接不接受）同样：weight = 人格+信任+库存的直接函数，
  不预测"薇拉被我拒后会怎样"并据此权衡。

## 附：当前证据链的量化印证

200 种子扫描只有一条完整因果模式（begging→refusal→trust collapse→reflection，
3/200），指纹 11 种但**机制同构**——正是"参数有随机、解释无分歧"的必然结果。

## 重构方向（按 GPT 三刀，实现顺序）

1. **切断"事件→状态变化"**：新建 `cognitive_transition.gd` 统一入口，
   事件强制经过 `SubjectiveEvent → 记忆检索 → Appraisal → Interpretation（多解释竞争）
   → Belief/Emotion/Relationship/Goal 更新`。删除 `_do_request` 直调
   `on_help_*`、删除 11 处情绪旁路、删除 ToM 固定增量更新。
2. **Utility 从"评动作"改为"评预测后果"**：`action_forecaster.gd` 用**行动者自己的
   信念**（非上帝视角）预测候选行动的后果与社会反应；决策评价预测结果；
   记录预测 vs 实际 → 社会预测误差 → 修正 ToM 响应模型。
3. **Reflection 从计数器改为解释竞争**：拒绝/帮助事件产生候选解释分布
   （自私/他也缺粮/不信任我/储备应急……），权重由信念×ToM×人格动力×情绪决定；
   新证据（目击他空手而归）降低"自私"权重、抬升"缺粮"权重——允许误解与修正。
4. 配套：结构化 Proposition 信念（证据累积式）；Norm 拆 personal/descriptive/injunctive；
   Relationship 拆 benevolence/reliability/obligation/fear 四维（trust 变显示综合值）；
   ConsiderationSet + DO_NOTHING/AVOID 合法行动；PersonalityDynamics 控制更新速率
   而非行为倍率；DecisionTrace v3（感知/检索/解释/预测/误差全程留痕）。

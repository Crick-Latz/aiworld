# P1.6 认知差距审计：Epistemic Agency & Generalized Social Cognition（2026-09-06）

结论先行：P1.5 让 NPC 会"解释世界"，但 NPC 仍不会"主动认识世界"，
且认知链深度绑定 food_request 一个领域。十项审计逐条如下（全部基于代码证据）。

## 1. 哪些行动真正使用 ActionForecaster？

只有 **2 处**：
- `action_registry.gd _request`：`request_expected_utility()`（求助的期望效用）
- `social_system.gd evaluate_food_request`：`refusal_social_cost / acceptance_social_gain / forecast_reactions`

## 2. 哪些行动仍只评价当前 utility？

其余全部 15 个行动（forage/drink/fish/shells/shelter/craft/fire/explore/ruins/
socialize/share/eat/rest/gather_wood/sit_by_fire/keep_distance/do_nothing）：
`当前状态 → 手工 utility → softmax`。第二刀实际完成度 =
**food-request domain 的 model-based decision**，不是 general model-based cognition。

## 3. CognitiveTransition 有多少 event_type 专属分支？

7 组：food_request_refused（proposer/actor 两路）、food_request_accepted（proposer）、
shared_food（recipient）、socialized（陪伴）、foraged/fished/ruins_loot/explored_found
（has_food 证据）、foraged_empty/fished_empty/ruins_empty（反证+weaken）、
_update_descriptive_norms 的 accepted/refused/shared 三分支。

## 4. Interpretation 有多少具体事件专属解释？

2 个事件类 × 手写候选：refusal 5 候选（selfish/also_starving/distrusts_me/
saving_reserve/dislikes_me）、acceptance 4 候选。若直接加 water/tool/medicine
request 各写 5 个 → 回到高级硬编码剧情系统。

## 5. NPC 是否读取其他角色真实 need/inventory？【信息泄漏，本轮修复】

三处：
- `social_system.gd`：`proposer["needs"]["hunger"]` → visible_need ——**决策者读对方真实饥饿**
- `island_simulation.gd _do_share`：遍历读所有人真实 hunger 挑"最饿者"——**分享者读他人真实饥饿**
- `island_simulation.gd _update_nearby_info`：`someone_hungry_nearby` 标志由真实 hunger>600 生成，
  进入 share/socialize 的效用计算

## 6. Perception 是否具有不确定性？

无。`subjective_event.gd certainty = 1.0` 恒定——"看见=完全看对"。

## 7. Belief 是否真正结构化？

否。BeliefStore 核心仍是字符串 statement（"欧恩 不肯帮我"）；Reflection 写入/读取
都走字符串。ToM 有证据列表但只有 3 个固定槽的 value。

## 8. ToM 能否表达任意属性/目标？

不能。固定槽 has_food/generous/reliable + response_model 四维。
无法表达"欧恩重视食物安全=0.8""欧恩此刻需要水=0.6"。

## 9. NPC 是否存在主动获取信息的行动？

**零**。没有任何 information-seeking 行动。信念修正完全依赖
"碰巧获得新证据"——被动认知。这是"拒绝→记恨→回避"闭环已涌现、
而"误解→调查→修正"闭环野外为 0 的直接原因。

## 10. LifeHistory 是否仍是 event_type → 固定参数映射？

是。`derived_sensitivities()` 按类型查表输出固定敏感度。未验证
"过去经历改变学习过程"（P1.5 的 dynamics 只接了 betrayal/food 二类敏感度）。

## 本轮（Phase 1）修复/新建清单

1. **感知门 Perception**：PerceivedActorState（可观察性分级：injury 高/hunger 中/
   inventory 隐藏/intention 不可见），堵住 3 处泄漏；测试 J（隐状态隔离）
2. **不确定性量化**：解释分布熵 → open_questions（"我想弄清楚他为什么拒绝"）
3. **认识行动 EpistemicActions**：ask_reason / observe_person / ask_third_party /
   wait_and_watch——效用 = λ_epi×EpistemicValue − SocialRisk，λ_epi 由人格动力决定
   （薇拉直问、欧恩暗看、卡德加问第三人）；测试 H（涌现）、I（方式分化）
4. **Claim ≠ Truth**：结构化声明，按说话者可靠度×一致性加权进信念；测试 M
5. 全量回归 + 提交

## Phase 2（下一轮）路线

- Semantic Event Schema（act/object/response 通用化）+ 通用动机本体
  （INCAPABLE/SELF_PRESERVATION/SELF_INTEREST/DISTRUST/...）
- 水/工具经数据配置接入（测试 L：禁止三套主逻辑）
- Promise/Favor/Obligation 闭环（测试 N）
- BeliefStore → 结构化 Proposition、ToM → 任意属性 MentalModel、Evidence 一等对象
- 校准（Brier）、认知效率、DecisionTrace v4、长程 sweep 指标

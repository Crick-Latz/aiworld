> 2026-09-10 状态说明：本文件保留为 P6.0 历史设计与人工模式摘要。所列文学案例尚未附逐条原文与审核证据，不能计作已完成的模型训练。当前证据导入与只读检索接口见 [小说认知接口](../../../../docs/NOVEL_COGNITION.md)。

# P6.0 — 叙事行为挖掘（Narrative Behavior Mining）

20 部荒岛/孤立求生/群体生存作品的行为模式抽取。**不是文学评论**——只抽 13 元组：Problem / Perceived Situation / Knowledge Used / Available Resources / Candidate Strategies / Chosen / Prerequisites / Tool-Capability / Social Dependency / Risk / Failure / Adaptation / Long-term Consequence。禁止照抄剧情/长篇引用/把文学夸张写进物理规则。

标记：`[S]`=SOURCE_DERIVED（作品可溯源）· `[E]`=ENGINEERING_INFERENCE（跨作品工程推断）· `[N]`=NOT_IMPLEMENTED（本版不实现）

## 作品 × 行为案例

**1. Robinson Crusoe（鲁滨逊）** `[S]`
- 沉船抢救：Problem=物资全失 → Strategy{捕捞残骸/徒手求生} → Chosen=多次返沉船 → Prereq=SWIM/CARRY → 长期=起步资本。
- 粮食弧：采野果→发现麦种→试种数年失败→轮作成功 `[N]`（农业=P6.5+）。
- 工具链：缺桶→烧陶→失败多次→成功 `[S]`：**工具的工具**模式原型。
- 孤独应对：记日记/驯羊/鹦鹉 `[S]` → ISOLATION→COMPANY。
- 风险：恐慌性囤积无计划（前期）→ 规划储藏（后期）。

**2. The Swiss Family Robinson（海角一乐园）** `[S]`
- 家庭分工：父规划/长子力工/次子博物——**专长分工**的教科书（EXPERTISE 层原型）。
- 树屋→崖堡→田园：住所渐进投资三级跳。
- 动物驯化（水牛/鸵鸟代步）`[N]`。

**3. The Mysterious Island（神秘岛）** `[S]`
- 工程复兴弧：火（透镜）→陶→铁→玻璃→电报——**每步以前步产物为工具**。
- 史密斯的知识中心地位：knowledge 权威 = 团队领导权 `[E]`。
- 失败：热气球逃跑失败→落地再规划。

**4. The Coral Island（珊瑚岛）** `[S]`
- 食物丰饶下的时间分配：探索/娱乐/装饰——**需求满足后行为多样化** `[E]`。
- 遇食人族：威胁阶梯（躲藏→援助受害者→武力介入）`[N]`。

**5. Two Years' Vacation（两年假期）** `[S]`
- 15 少年自治：选举→分工→派系（法英裔分裂）→分裂危机→重组——**制度从零涌现**的完整弧 `[S]`（P2 制度层的叙事验证）。
- 纪律执行者 Bry vs 实干 Gordon：两种领导原型。

**6. Island of the Blue Dolphins（蓝色海豚岛）** `[S]`
- 单人女性长期生存：围堰捕鱼/鸬鹚裙/洞穴冬储——低工具高知识密度路线。
- 等待救援 vs 离开的决定：ESCAPE_DESIRE 的心理经济学。
- 弟弟之死 → 单人 mourn/ISOLATION 深化。

**7. The Cay** `[S]`
- 失明少年+黑人水手：**能力残缺下的知识让渡**（Timothy 教盲童自理）——教学作为社会行为 `[N]`。
- 风暴应对：加固棚/绑自身——PREPARE 类计划（前瞻性 risk 处理）`[N]`。

**8. Kensuke's Kingdom（ Kensuke 的王国）** `[S]`
- 隐居者领地意识：私下入侵→愤怒→照顾→传授——** PROPERTY 边界 + 关系转变**弧。
- 长期隐居者的储存纪律与节制采集 `[S]`：PRESERVE 伦理。

**9. Lord of the Flies（蝇王）** `[S]`
- 制度崩溃弧：号角集会→规则遗忘→暴力权威（Jack）取代程序权威（Ralph）——**THREATEN 作为领导手段** `[N]`（P6.7/P6.8）。
- 信号火 vs 狩猎的资源冲突：长期目标败给短期需求 `[E]`。
- 替罪羊机制（Simon 之死）：群体恐惧→暴力投射 `[N]`。

**10. The Beach（海滩）** `[S]`
- 乌托邦的封闭性：准入控制/信息管制/对外隐瞒——**欺骗性制度维持** `[N]`。
- 稻田劳动分工与游客经济：生产结构决定权力结构 `[E]`。

**11. Nation（特里·普拉切特）** `[S]`
- 灾后双幸存者：知识互补（土著海岛知识×白人航海知识）——**异质知识的合作溢价** `[E]`。
- 疫苗接种的知识冲突：EXPERTISE 信任问题。

**12. On the Island** `[S]`
- 师生二人：照料关系（伤病/脱水）→ 依恋重构——SOCIAL_THREAT 缺失下的纯合作弧。
- 淡水优先级：水>食>庇护>信号 `[E]`。

**13. Beauty Queens（选美小姐荒岛）** `[S]`
- 性别分工的颠覆：化妆技能→工具化（发胶火炬）——**能力语义重构** `[E]`。
- 隐藏的公司阴谋：第三方恶意行为者 `[N]`。

**14. The Troop** `[S]`
- 寄生虫威胁下的隔离决策：牺牲少数保全多数——**伦理困境作为制度压力测试** `[N]`。
- 信任崩塌加速：隔离→猜疑链。

**15. The Blue Lagoon** `[S]`
- 无成人儿童的技能自悟：试错学习（毒浆果→呕吐→标记 avoidance）——**LEARNED_LOCAL 的代价形成** `[E]`。
- 青春期关系弧：同伴关系→伴侣关系 `[N]`。

**16. The Island of Doctor Moreau** `[S]`
- 造物伦理：技术能力无约束的恐怖——**知识的边界问题**（远期主题）。
- 兽人退化：制度消失后行为回退 `[E]`。

**17. Galápagos（冯内古特）** `[S]`
- 百万年视角：大脑过大是祸源——反讽参照（AIWord 刻意不做过强推理）。
- 供需错配的荒诞：船资源与技能错配 `[E]`。

**18. Pincher Martin（品彻·马丁）** `[S]`
- 濒死幻觉中的执着：贪婪人格的孤岛投射——**人格×极端处境**的叙事素材。
- 感知不可靠性：主观世界≠客观世界的文学极端版（P5 哲学的文学呼应）。

**19. The Raft（木筏）** `[S]`
- 海上漂流：水资源极限管理（配给/雨水收集）——RATION 模式 `[N]`。
- 信号失败循环：TLE 通信尝试→失败→再尝试——**希望管理** `[E]`。

**20. Masterman Ready** `[S]`
- 老水手知识 vs 父亲书本知识：**实践知识胜过理论知识**（EXPERTISE>CULTURAL 场景）`[E]`。
- 蜜蜂养殖/船骸利用：多样化生产 `[N]`。

## 跨案例模式（→ 已入 p6_behavior_pattern_library.md）

1. **三重门槛**（知识/观察/持有）在全部 20 部中反复出现 `[E]`。
2. **工具的工具**：Crusoe/神秘岛/Ready 的核心弧——P6.0 递归 planner 的叙事合法性 `[E]`。
3. **专长分工与合作溢价**：家庭罗宾逊/两年假期/Nation `[S]`。
4. **制度涌现-崩溃-重建**：两年假期/蝇王/海滩——P2 已实现涌现，崩溃与暴力留 P6.7/6.8 `[S]`。
5. **失败-解释-调整循环**：几乎所有作品的生存学习曲线 `[E]`——P1.6 解释系统 + ThreadEngine failure 节点已承载。
6. **单人长期生存是例外且高心理代价**：4/20 `[S]`——社会依赖应为一等公民（P6.0 KK 门）。

## 候选能力/affordance/计划模式清单（工程转化，[N] 项不进本版）

- 能力：CUT/PIERCE/BIND/BUILD_BASIC/BUILD_STRONG/LIGHT/COOK/PRESERVE/HUNT_*/FISH/TRAP/NAVIGATE/WATER_TRANSPORT/STORE/DEFEND/THREATEN `[已定义]`；FLEE/AMBUSH/FORM_COALITION `[N]`
- affordance：wood_fuel/wood_structure/craft_spear/make_fire/build_shelter/build_raft/set_trap/bind_cord `[已实现]`；smoke_preserve/plant_garden/tame_animal/signal_fire `[N]`
- 计划模式：tool-prerequisite 链 `[已实现]`；rationing `[N]`；prepare-for-storm `[N]`；teach-skill `[N]`；territory-claim `[N]`

# P6.0 — 行为模式库（Behavior Pattern Library）

从 20 部荒岛/孤立求生小说抽象（挖掘细节见 p6_narrative_behavior_mining.md）。
目的：不是穷举行为，而是**抽象共同结构**——问题 → 知识 → 手段 → 前置 → 后果。
标记：`SOURCE_DERIVED`（小说可溯源）/ `ENGINEERING_INFERENCE`（工程推断）/ `NOT_IMPLEMENTED`（本版未实现）。

## 模式结构（统一骨架）

```text
Problem（问题） → Perceived Situation（感知处境） → Knowledge Used（用到的知识）
→ Candidate Strategies（候选手段，≥2） → Chosen（选择 + 选择依据）
→ Prerequisites（前置：能力/工具/材料/社会） → Execution → Risk/Failure
→ Adaptation（失败后的调整） → Long-term Consequence（长期后果）
```

## 二十三类问题域的模式（SOURCE_DERIVED 为主）

### Food
- 采集（已知植物点 → 定期回访 → 枯竭 → 扩大搜索）`已实现（P5 浆果）`
- 狩猎（见猎物 → 缺猎具 → 造矛/陷阱 → 追猎/守陷阱）`NOT_IMPLEMENTED（P6.5）`
- 渔捞（浅滩手捉 → 鱼叉 → 网/堰）`部分（鱼叉已有，网/堰 NOT_IMPLEMENTED）`
- 储存加工（ surplus → 烟熏/晒干/坑藏 → 抗荒）`NOT_IMPLEMENTED（PRESERVE 能力已定义）`
- **共同结构**：食物手段从"捡"到"捕"到"养"到"存"，每一步都以工具/知识前置为门槛。

### Water
- 找水（地形知识：低处/植被/动物足迹 → 泉/溪）；集水（叶面凝露/雨水坑）；储水（大型贝壳/竹筒/坑）。
- **共同结构**：水的问题常分解为"发现→运送→储存"三段，各需不同能力（NAVIGATE/CARRY/CONTAIN）。

### Shelter / Temperature / Health
- 就地遮蔽（岩洞/树窝）→ 改良（枝叶棚）→ 建造（木石结构）；保暖（火/干草/挤在一起）；伤病（休息/草药/他人照料）。
- **共同结构**：住所是渐进投资——每次升级消耗更多前置（BUILD_BASIC→BUILD_STRONG），收益是长期风险下降。

### Predator / Threat / Violence `NOT_IMPLEMENTED（P6.7）`
- 回避（结伴/火/避开区域）→ 驱赶（火把/噪音/武器威慑）→ 猎杀（合作围猎）→ 逃亡（筏/高地）。
- **共同结构**：威胁应对是能力阶梯：FLEE < DEFEND < THREATEN < ATTACK；威慑依赖对方对我能力的**认知**（THREATEN 需要被看见才有效）——社会认知与暴力的接口。

### Tool shortage / Production / Construction
- 通用模式（ SOURCE_DERIVED 高频）：**需要 X → 造不出 X → 造能造 X 的工具（工具的工具）**——燧石→刀→木料→棚。
- 材料替换（无麻绳 → 树皮纤维/藤/兽筋）：**备选材料用多条规则表达**（P6.0 已采用 AND-材料 + 多规则备选）。

### Transport / Storage / Escape
- 搬运（拖/扛/独轮/筏运）；储藏（挂高防兽/坑藏防潮/标记防抢）；逃离（信号火→船→漂流）。
- **共同结构**：逃离 = 大型多前置计划（材料×能力×知识），且几乎总是**社会依赖**的（单人造船的失败率在小说里极高）。

### Exploration
- 定向探索（沿海岸线/河流——保证可返回）vs 自由探索（内陆——易迷路）。
- **共同结构**：探索策略受空间知识约束（P5 已实现：last_seen/coverage/迷路）。

### Resource scarcity / Competition / Property `部分 NOT_IMPLEMENTED`
- 稀缺 → 配给（定额/顺序）→ 储藏私有化 → 偷窃/争夺 → 规则/惩罚。
- **共同结构**：资源竞争是制度（P2）与暴力（P6.7）的交汇点——AIWord 已有制度层，缺暴力终端。

### Cooperation / Leadership / Trust / Coalition `部分已有`
- 合作模式：分工（守火/觅食/建造轮班）；领导（能力型/魅力型/暴力型）；信任（共患难积累/一次背叛崩塌）；联盟（多数派/弱者联合）。
- **共同结构**：领导权的确立几乎总经过"危机→某人提出可行方案→成功→权威"——计划能力（P6）与权威（P2 AUTHORITY_THREAD）的天然接口。

### Deception / Trade `NOT_IMPLEMENTED`
- 欺骗：隐瞒发现（私藏食物）/夸大能力/假信号；交易：以物易物/劳务交换/信息换保护。
- **共同结构**：欺骗与交易的共同前置是**信息不对称**——AIWord 的隐藏状态哲学天然支持。

### Isolation（孤独）
- 独处者：自言自语/写日记/驯化动物为伴/规律作息维持理智（SOURCE_DERIVED：Crusoe/Blue Dolphins/Pincher Martin）。
- **共同结构**：孤独是 ISOLATION problem——满足物是 COMPANY/CONTACT；现有的 social need + Owen 反转现象已是该模式的雏形。

## 跨域涌现模式（ENGINEERING_INFERENCE）

1. **手段阶梯**：几乎所有问题域都有"直接取用 < 工具辅助 < 系统生产"三级结构——对应 Capability 的获取路径。
2. **失败驱动的学习**：小说中的关键转折几乎都是"计划失败 → 解释原因 → 改进手段"——对应 ThreadEngine 的 failure 节点 + P1.6 的解释系统。
3. **知识×观察×持有的三重门槛**：知道方法、看见材料、拿到材料是三件事（P6.0 PK-B/C 门锁的就是这个）。
4. **社会依赖是常态而非例外**：20 部中单人成功长期生存的只有 4 部（且其中 2 部主角接近疯癫）——合作能力本身是最高阶的生存能力。

# P4 完工报告（供 GPT 评审）

日期：2026-09-06 ｜ 回归：**559/559 全绿**（18 套件）
状态：**P4 全阶段完成（P4-1 Thread Engine + P4-2 Summary + P4-3 Observer Panel）**

---

## 一、P4 回答的核心问题

> "为什么十天前那次拒绝和今天这次搬家属于同一段历史？"

**不是 Story Director**——系统不制造剧情。ThreadEngine 只是从真实事件流中**识别**跨天事件链，全部使用结构化 ID（promise dyad / institution_id / question dyad），绝不按时间邻近或关键词关联。

## 二、P4 交付物

### P4-1：StoryThread + ThreadEngine

- **7 类线程**：PROMISE / EPISTEMIC / RELATIONSHIP_CONFLICT / RECIPROCITY / INSTITUTION_CONFLICT / AUTHORITY / RELOCATION
- **三级关联**：显式 ID > 因果结构边 > 同参与者+兼容语义+关系链接
- **状态机**：OPEN → ACTIVE → DORMANT（120 tick 无事件）→ RESOLVED（仅凭结构化证据）
- **重激活**：DORMANT + 新相关事件 → 同 thread_id ACTIVE
- **永久原则**：READ-ONLY / 不增加 Utility / 不创建 Goal / 不改变 Emotion / 不触发 Event

### P4-2：ThreadSummaryRenderer

三种深度确定性渲染：
- **TIMELINE**：`第3天 欧恩拒绝了薇拉 / 第4天 薇拉形成敌意解释 / ...`
- **SUMMARY**：`欧恩对卡德加许下的承诺，经过 17 天终于兑现了。`
- **TITLE**：`● 薇拉、欧恩的疑问`（状态图标 + 标题）

### P4-3：Observer 故事线面板

游戏内显示（金色"── 故事线 ──"面板）：
```
● 欧恩、卡德加的互助
  欧恩与卡德加之间形成了互助的默契。

○ 薇拉对欧恩拒绝原因的疑问
  薇拉心中的一个疑问渐渐沉寂了，但并未消散。

✓ 欧恩对卡德加的承诺
  欧恩对卡德加许下的承诺，经过 17 天终于兑现了。
```

## 三、关键测试（TA-TI，10/10）

| 测试 | 验证 |
|---|---|
| **TA** | 承诺 Day 1 → 400 tick（17天）无关事件 → Day 18 兑现 = **同一线程 RESOLVED** |
| **TB** | tick+1 的天气不入承诺线程（**邻近≠关联**） |
| **TC** | 120 tick 无事件 → DORMANT，线程保留 |
| **TE** | **10000 tick 无证据仍 DORMANT**（时间≠解决） |
| **TD** | DORMANT + 新事件 → 同 thread_id 重激活 |
| **TH** | ThreadEngine ON/OFF → **世界 hash 完全一致** |
| **TI** | 同历史 → 同线程（确定性） |

## 四、代码位置

| 文件 | 行数 | 内容 |
|---|---|---|
| `narrative/story_thread.gd` | 200 | 线程 schema + 3-tier 关联 + 状态机 + resolution |
| `narrative/thread_engine.gd` | 120 | ThreadSeed 检测 + process + build_thread_ir |
| `narrative/thread_summary_renderer.gd` | 95 | TIMELINE/SUMMARY/TITLE 三深度渲染 |
| `scenes/observer/observer_main.gd` | ThreadEngine 接入（每 30 tick） |
| `scenes/observer/observer_hud.gd` | 故事线面板渲染 |
| `test/p4_threads.gd` | TA-TI 七项测试 |

## 五、P4 禁止事项遵守

✅ 不修改 cognition / 不制造事件 / 不修改 Utility / 不强迫闭合 / 不按时间邻近连接 / 不靠关键词连接 / 不要求所有 Beat 加入 Thread / 不让 LLM 创建 Thread / 不让 LLM 决定 Thread status / 不做 Story Director / 不做 Quest Generator

## 六、项目最终全景

```
P1.5–P2.1.1  认知与社会核心          ✅ FROZEN
P3a           叙事层（IR→Claims→Renderer）✅ Live Smoke 通过
P3b           对话表面（SpeechAct→Text）  ✅ Text Invariance
P3c           角色连续性（L/M/S 表达）    ✅ Stable but Plastic
P4             长时程故事线（跨天事件链）  ✅ READ-ONLY / 确定性
```

从"NPC 会自己活" → "会说自己活出来的故事" → "玩家看懂因果关系" → **"系统知道哪些跨越很久的事情属于同一个故事"**。

下一步候选（等 GPT/用户）：LLM Thread Renderer（复用 claim package / Validator / fallback）或 Long-horizon 运行验证（500+ seed × 2000+ tick 扫描故事线多样性）。

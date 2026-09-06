# P3b Dialogue Surface 完工报告（供 GPT 评审）

日期：2026-09-06 ｜ 回归：**527/527 全绿**（17 套件）
状态：P3b-1/2/3/4/5 全部完成。**未进入 P3c。**

---

## 一、Smoke 前检查（GPT 点名的两处，均已修）

1. **confidence_hedge**：`"显然"` → `"很确信"`（0.81 仍是角色主观置信，非客观确定性）
2. **PROMPT_SYSTEM 因果约束**：更新为引用 claim 类型（"因果连接词只允许出现在 type 为 CAUSAL_LINK 的主张支撑的句子中"），不再一刀切禁止——P3a-2.1 已从批准边生成合法因果主张

## 二、P3b 核心交付

### P3b-1 SpeechAct Schema（`narrative/speech_act.gd`）

```
SpeechAct {
    speech_id, speaker_id, audience_ids[]
    act_type          # 16 种——只接系统真实决定的行为
    communicative_goal
    propositions[]    # 结构化命题（LLM 不得添加）
    sincerity         # SINCERE（第一版；欺骗由 simulation 决定）
    stance            # -1/0/1
    emotional_tone    # {anger, sadness, expressiveness, directness, politeness}
    publicness        # PUBLIC / PRIVATE
    source_event_ids[], source_trace_ids[]
}
```

**三层分离**（GPT 第 2 条）保证：Speaker Belief（真实信念）/ Communicated Claim（传达的命题，可撒谎）/ Surface Utterance（LLM 台词）——永不互相代替。

**接收方走结构化 Claim**（第 12 条），绝不重新 NLP 解析 LLM 文本。

### P3b-2 TemplateDialogueRenderer（`narrative/template_dialogue_renderer.gd`）

16 种行为类型的确定性模板，由说话者的 expressiveness/politeness/anger 调制表面措辞（**非固定口癖**，第 9 条）。LLM 不可用时保底。

### P3b-3 DialogueValidator（`narrative/dialogue_validator.gd`）

- speech_id 匹配
- **立场反转检测**：REFUSE 被渲染为"好的，我给你" → E_STANCE_REVERSED 拒绝（DC）
- 不得添加未经系统决定的承诺（E_ADDED_PROMISE，DD）
- 不得添加威胁（E_ADDED_THREAT）

### P3b-4 Text Invariance（**最重要的架构测试**）

**DB 测试**：同一 SpeechAct + 三种完全不同的渲染文本 → 世界状态 hash（needs/inventory/emotions/tick/events）**完全不变**。

> **"LLM 负责演戏，不负责决定角色的人生"** ——架构级保证。

### P3b-5 Observer 对话转录

游戏内显示：金色"── 对话 ──"头 + 蓝色角色名 + 台词 + 灰色行为类型。每行带 seq 供未来下钻。

## 三、测试（7/7，套件 56/56）

| 测试 | 断言 |
|---|---|
| p3b_event_found | 真实拒绝事件可提取 |
| p3b_speech_act_created | SpeechAct 构建正确（REFUSE_REQUEST） |
| **p3b_db_text_invariance** | 三渲染器，世界 hash 不变 |
| p3b_dc_refusal_cannot_become_acceptance | "好的，我给你"→Validator 拒绝 |
| p3b_dc_valid_refusal_passes | 合法拒绝通过 |
| p3b_dd_no_added_promise | "我保证以后一定给你"→拒绝 |
| **p3b_dh_character_voice** | 三角色同一拒绝行为，三种不同措辞 |

## 四、DH 角色声音示例（真实输出）

同一 `REFUSE_REQUEST + reason=own_scarcity`：
- **薇拉**（expressiveness 0.85, politeness 0.30）："不行，我自己也得留一点。"
- **欧恩**（expressiveness 0.15, politeness 0.70）："我也想帮你，可现在真的拿不出来。"
- 语义完全相同（同 claim_ids/stance），只有表面措辞不同

## 五、禁止事项遵守

LLM 不能：决定行动✓ 决定 SpeechAct✓ 创建 Claim✓ 修改 Belief✓ 修改 Emotion✓ 修改 Relationship✓ 修改 Promise✓ 修改 Institution✓ 创建 NPC✓ 自由多轮聊天✓ 解析自然语言回写 cognition✓

## 六、代码位置

| 文件 | 内容 |
|---|---|
| `narrative/speech_act.gd`（新建 ~130 行） | Schema + from_event 适配器（16 行为类型映射） |
| `narrative/template_dialogue_renderer.gd`（新建 ~75 行） | 确定性模板 + 角色风格调制 |
| `narrative/dialogue_validator.gd`（新建 ~55 行） | 立场反转/承诺/威胁检测 |
| `scenes/observer/observer_main.gd` | 事件→SpeechAct→台词提取 |
| `scenes/observer/observer_hud.gd` | 对话面板渲染 |
| `test/p3_narrative.gd` | +7 断言（56 总） |

## 七、下一步

- LLM DialogueRenderer（真实 API，复用 NarrativeRenderer 契约 + DialogueValidator）——待凭据
- P3c Long-horizon Expression / Character Continuity（GPT 已定义方向）

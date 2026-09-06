class_name PersonalityProfile
extends RefCounted
## 人格档案（阶段 B，M06）：性格特质 + 信念 + 情绪基调。
## 性格不是固定标签，是响应曲线的参数修饰器：
##   "乐观" 不等于 happiness=0.8，而是「挫折后恢复曲线的斜率更平缓」。
##   "自私" 不等于 selfishness=0.5，而是「分享行为的效用曲线整体下移」。
## 信念可持有多个且矛盾——决策时由当时的身体/情绪状态决定哪个占上风。
## 情绪是短期状态，受事件影响，会压过逻辑（人不是永远讲逻辑的）。

# ── 性格特质（0..1，作为曲线修饰器使用）──
var traits := {
	# 韧性：遭遇挫折后恢复速度（越高恢复越快）
	"resilience": 0.5,
	# 好奇心：对未知事物/地点的探索欲望
	"curiosity": 0.5,
	# 行动导向：想做的事立刻做（vs 先计划）
	"action_bias": 0.5,
	# 谨慎：风险评估放大系数（越高越怕冒险）
	"caution": 0.5,
	# 同理心：感知他人痛苦的敏感度
	"empathy": 0.5,
	# 社交性：独处时的不适增速
	"sociability": 0.5,
	# 利他倾向：帮助他人（vs 先保自己）
	"altruism": 0.5,
	# 表达力：能否准确传达想法（低→被误解为冷漠）
	"expressiveness": 0.5,
	# 冲突回避：面对争执时逃避 vs 对抗
	"conflict_avoidance": 0.5,
	# 务实度：只做确定有用的事（vs 可能有用也做）
	"pragmatism": 0.5,
}

# ── 信念（多个可矛盾，权重随事件改变）──
# 格式: { "信念文本": {"weight": 0.0..1.0, "source_event": seq_or_null} }
var beliefs := {}

# ── 情绪状态（-1..1，短期，受事件影响）──
var emotions := {
	"joy": 0.0,        # 喜悦（正向事件积累）
	"fear": 0.0,       # 恐惧（危险事件触发）
	"anger": 0.0,      # 愤怒（被冒犯/不公）
	"sadness": 0.0,    # 悲伤（失去/失败）
	"guilt": 0.0,      # 内疚（自己违反了自己的规范）
	"trust_open": 0.5, # 信任开放度（高→更容易信任他人）
}

func _init(trait_overrides := {}, initial_beliefs := {}) -> void:
	for k in trait_overrides:
		if traits.has(k):
			traits[k] = clampf(float(trait_overrides[k]), 0.0, 1.0)
	for b in initial_beliefs:
		add_belief(b, initial_beliefs[b])

func add_belief(text: String, weight: float = 0.5, source_event: int = -1) -> void:
	beliefs[text] = {"weight": clampf(weight, 0.0, 1.0), "source_event": source_event}

func strengthen_belief(text: String, delta: float) -> void:
	if beliefs.has(text):
		beliefs[text]["weight"] = clampf(float(beliefs[text]["weight"]) + delta, 0.0, 1.0)

func weaken_belief(text: String, delta: float) -> void:
	strengthen_belief(text, -delta)

# 获取某类信念的最大权重（例：所有关于"合作"的信念中，最强的那个）
func strongest_belief_containing(keyword: String) -> float:
	var max_w := 0.0
	for text in beliefs:
		if text.find(keyword) >= 0:
			max_w = maxf(max_w, float(beliefs[text]["weight"]))
	return max_w

# ── 情绪更新（由事件触发）──
func adjust_emotion(key: String, delta: float) -> void:
	if emotions.has(key):
		emotions[key] = clampf(float(emotions[key]) + delta, -1.0, 1.0)

# 情绪恢复（每 tick 向 0 衰减，韧性越高衰减越快）
# trust_open 是性格基线不是心情——不参与衰减（否则 50 tick 后人人归零）
func decay_emotions() -> void:
	var decay_rate := 0.01 + float(traits["resilience"]) * 0.02
	for key in emotions:
		if key == "trust_open":
			continue
		var v: float = emotions[key]
		if v > 0:
			emotions[key] = maxf(0.0, v - decay_rate)
		elif v < 0:
			emotions[key] = minf(0.0, v + decay_rate)

# ── 身体状态对性格的动态修饰 ──
# 返回修饰后的有效特质值（不是改变基础值，是临时调整）
func effective_trait(trait_name: String, physical_state: Dictionary) -> float:
	var base: float = traits.get(trait_name, 0.5)
	var modifier := 1.0

	# 饥饿放大负面特质
	var hunger: float = physical_state.get("hunger", 0.0) / 1000.0
	if hunger > 0.7:
		if trait_name in ["altruism", "empathy", "sociability"]:
			modifier -= (hunger - 0.7) * 1.5  # 饿到极致，利他/同理心/社交全面下降
		elif trait_name in ["caution", "conflict_avoidance"]:
			modifier -= (hunger - 0.7) * 0.5  # 饿急了会冒险

	# 疲劳降低决策质量
	var energy: float = physical_state.get("energy", 1000.0) / 1000.0
	if energy < 0.3:
		if trait_name in ["action_bias", "pragmatism"]:
			modifier -= (0.3 - energy) * 1.0  # 累了变冲动/不理性
		elif trait_name == "expressiveness":
			modifier -= (0.3 - energy) * 0.5  # 累了说不出话

	# 恐惧压过逻辑
	var fear: float = emotions["fear"]
	if fear > 0.5:
		if trait_name == "curiosity":
			modifier -= (fear - 0.5) * 2.0  # 恐惧时不敢探索
		elif trait_name == "caution":
			modifier += (fear - 0.5) * 2.0  # 恐惧时更谨慎

	# 愤怒影响判断
	var anger: float = emotions["anger"]
	if anger > 0.5:
		if trait_name == "conflict_avoidance":
			modifier -= (anger - 0.5) * 2.0  # 愤怒时不再回避冲突
		elif trait_name == "empathy":
			modifier -= (anger - 0.5) * 1.5  # 愤怒时失去同理心

	return clampf(base * modifier, 0.0, 1.0)

# ── 快照 ──
func snapshot() -> Dictionary:
	return {
		"traits": traits.duplicate(),
		"beliefs": beliefs.duplicate(),
		"emotions": emotions.duplicate(),
	}

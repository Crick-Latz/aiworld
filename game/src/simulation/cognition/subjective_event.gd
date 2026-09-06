class_name SubjectiveEvent
extends RefCounted
## 主观事件（P1.5 第四条）：世界事件流记录的是 WORLD FACT；
## 角色真正处理的是自己的主观版本——带着"我当时知道什么、以为什么"。
## 同一次"欧恩拒绝薇拉"，薇拉眼里和卡德加眼里是两个不同的主观事件。

static func build(observer: Dictionary, event: Dictionary, relationships) -> Dictionary:
	var me := str(observer.get("id", ""))
	var actor_id := str(event.get("actor_id", ""))
	var tom: TheoryOfMind = observer.get("tom", null)
	var norms: Dictionary = observer.get("norms", {})
	var personal: Dictionary = norms.get("personal", norms)

	# 对手方：从我（观察者）的视角确定这件事"关乎我和谁"
	var counterpart := actor_id
	if actor_id == me:
		counterpart = str(event.get("to_id", event.get("proposer_id", event.get("target_id", ""))))
	elif me == str(event.get("proposer_id", "")):
		counterpart = actor_id
	elif me == str(event.get("to_id", "")):
		counterpart = actor_id

	# 当刻认知快照：我以为他粮多吗？我信他吗？我自己饿吗？我觉得人该分享吗？
	var sem := ResourceSpec.semantics_of(event)
	var predicate := "has_food"
	if sem.has("object"):
		predicate = ResourceSpec.spec(str(sem["object"]))["predicate"]  # 资源谓词由语义决定：has_food/has_water/has_spear
	var believed_rich := 0.0
	var believed_generous := 0.0
	if tom != null and counterpart != "":
		believed_rich = tom.raw_belief(counterpart, predicate)
		believed_generous = tom.raw_belief(counterpart, "generous")
	var trust_toward := 0
	if relationships != null and counterpart != "":
		trust_toward = relationships.composite_trust(me, counterpart)

	var se := {
		"type": str(event.get("type", "")),
		"seq": int(event.get("seq", 0)),
		"tick": int(event.get("tick", 0)),
		"observer_id": me,
		"actor_id": actor_id,
		"counterpart_id": counterpart,
		"is_self_event": actor_id == me,
		"role": _role_of(me, event),
		"certainty": 1.0,  # 只有目击者会走到这里
		"context": {
			"believed_rich": believed_rich,
			"believed_generous": believed_generous,
			"trust_toward_counterpart": trust_toward,
			"own_hunger": clampf(float(observer.get("needs", {}).get("hunger", 0)) / 1000.0, 0.0, 1.0),
				"own_thirst": clampf(float(observer.get("needs", {}).get("thirst", 0)) / 1000.0, 0.0, 1.0),
			"personal_sharing": float(personal.get("sharing", 0.5)),
			"descriptive_sharing": float(norms.get("descriptive", {}).get("sharing", 0.5)),
			"text": str(event.get("text", "")),
			"reason": str(event.get("reason", "")),
		},
		"interpretation": {},  # 由 Interpretation 填充
		"semantics": sem,
	}
	return se

## 我在这个事件里扮演什么角色（决定走哪条评价/解释路径）
static func _role_of(me: String, event: Dictionary) -> String:
	if me == str(event.get("actor_id", "")):
		return "actor"
	if me == str(event.get("proposer_id", "")):
		return "proposer"     # 我求助，他回应
	if me == str(event.get("to_id", "")):
		return "recipient"    # 他分给了我
	if me == str(event.get("target_id", "")):
		return "target"       # 他向我开口
	return "witness"

class_name PerceivedCapabilityAdapter
extends RefCounted
## P6.1 §9-11 伙伴能力感知适配器——极薄，读现有 ToM 证据，不读真值。
## 原则：没有充分结构证据 → 返回 []（UNKNOWN）。宁可漏掉求助方案，也不能全知。
## 不新造第二套 ToM。

## ToM 谓词槽 → 可感知能力域（只列已有证据槽；未来见对方造船成功可加 WOODWORKING）
const SLOT_TO_CAPABILITY := {
	"has_spear": ["HUNT", "HUNT_MEDIUM"],   # 我见过他持矛 → 他多半能狩猎
}

static func perceived_capabilities(actor: Dictionary, peer_id: String) -> Array:
	var tom = actor.get("tom", null)
	if tom == null:
		return []
	var out: Array = []
	for slot in SLOT_TO_CAPABILITY:
		if float(tom.belief_about(peer_id, slot)) > 0.4:
			for cap in SLOT_TO_CAPABILITY[slot]:
				if not out.has(str(cap)):
					out.append(str(cap))
	out.sort()
	return out

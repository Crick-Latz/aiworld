extends RefCounted
class_name MaterialHolderBeliefAdapter

const DEFAULT_MAX_AGE_TICKS := 72

static func observe_event(observer: Dictionary, event: Dictionary, now_tick: int) -> void:
	var observer_id := String(observer.get("id", ""))
	var event_type := String(event.get("type", ""))
	var actor_id := String(event.get("actor_id", ""))
	if observer_id.is_empty():
		return
	_ensure_store(observer)
	match event_type:
		"gathered_wood":
			_observe_gain(observer, actor_id, "wood", maxi(1, int(event.get("wood", 1))), now_tick, event)
		"gathered_shells":
			_observe_gain(observer, actor_id, "shells", maxi(1, int(event.get("shells", 1))), now_tick, event)
		"ITEM_TRANSFER_COMPLETED":
			_observe_exact(observer, String(event.get("from_actor_id", "")), String(event.get("item_id", "")), maxi(0, int(event.get("giver_after", 0))), now_tick, event)
			_observe_exact(observer, String(event.get("to_actor_id", "")), String(event.get("item_id", "")), maxi(0, int(event.get("receiver_after", 0))), now_tick, event)
		"crafted", "shelter_built", "fire_built", "fire_started":
			_mark_actor_beliefs_stale(observer, actor_id, now_tick)

static func candidates(actor: Dictionary, item_id: String, visible_actor_ids: Array,
		relationships: RelationshipStore, now_tick: int, excluded_actor_ids: Array = [],
		max_age_ticks: int = DEFAULT_MAX_AGE_TICKS) -> Array:
	var out: Array = []
	var actor_id := String(actor.get("id", ""))
	var store: Dictionary = actor.get("material_holder_beliefs", {})
	var tom: TheoryOfMind = actor.get("tom", null)
	var keys: Array = store.keys()
	keys.sort()
	for key in keys:
		var belief: Dictionary = store[key]
		var holder_id := String(belief.get("actor_id", ""))
		if holder_id.is_empty() or holder_id == actor_id or excluded_actor_ids.has(holder_id):
			continue
		if String(belief.get("item_id", "")) != item_id or bool(belief.get("stale", false)):
			continue
		var evidence_tick := int(belief.get("evidence_tick", -1))
		if evidence_tick < 0 or evidence_tick > now_tick:
			continue
		if max_age_ticks >= 0 and now_tick - evidence_tick > max_age_ticks:
			continue
		if not visible_actor_ids.has(holder_id):
			continue
		var raw_trust := relationships.composite_trust(actor_id, holder_id)
		var cooperation := clampf((float(raw_trust) + 1000.0) / 2000.0, 0.0, 1.0)
		if tom != null:
			cooperation = clampf((cooperation + tom.response_belief(holder_id, "shares_with_me")) * 0.5, 0.0, 1.0)
		out.append({"actor_id": holder_id, "item_id": item_id,
			"believed_quantity": maxi(0, int(belief.get("believed_quantity", 0))),
			"confidence": clampf(float(belief.get("confidence", 0.0)), 0.0, 1.0),
			"evidence_tick": evidence_tick, "visible": true,
			"relationship": clampf(float(raw_trust) / 1000.0, -1.0, 1.0),
			"expected_cooperation": cooperation, "distance": 0.0,
			"source": String(belief.get("source", "WITNESSED_WORLD_EVENT"))})
	return out

static func mark_refuted(actor: Dictionary, holder_id: String, item_id: String, now_tick: int) -> void:
	var store: Dictionary = actor.get("material_holder_beliefs", {})
	var key := _key(holder_id, item_id)
	if not store.has(key):
		return
	var belief: Dictionary = store[key]
	belief["stale"] = true
	belief["refuted_tick"] = now_tick
	belief["confidence"] = minf(float(belief.get("confidence", 0.0)), 0.2)
	store[key] = belief
	actor["material_holder_beliefs"] = store

static func snapshot(actor: Dictionary) -> Dictionary:
	return (actor.get("material_holder_beliefs", {}) as Dictionary).duplicate(true)

static func _ensure_store(actor: Dictionary) -> void:
	if typeof(actor.get("material_holder_beliefs", null)) != TYPE_DICTIONARY:
		actor["material_holder_beliefs"] = {}

static func _observe_gain(observer: Dictionary, holder_id: String, item_id: String, quantity: int,
		now_tick: int, event: Dictionary) -> void:
	if holder_id.is_empty() or holder_id == String(observer.get("id", "")) or item_id.is_empty():
		return
	var store: Dictionary = observer.get("material_holder_beliefs", {})
	var key := _key(holder_id, item_id)
	var prior: Dictionary = store.get(key, {})
	store[key] = {"actor_id": holder_id, "item_id": item_id,
		"believed_quantity": maxi(0, int(prior.get("believed_quantity", 0))) + quantity,
		"confidence": maxf(0.65, float(prior.get("confidence", 0.0))),
		"evidence_tick": now_tick, "source_event_id": int(event.get("seq", -1)),
		"source": "WITNESSED_ACQUISITION", "stale": false}
	observer["material_holder_beliefs"] = store

static func _observe_exact(observer: Dictionary, holder_id: String, item_id: String, quantity: int,
		now_tick: int, event: Dictionary) -> void:
	if holder_id.is_empty() or holder_id == String(observer.get("id", "")) or item_id.is_empty():
		return
	var store: Dictionary = observer.get("material_holder_beliefs", {})
	store[_key(holder_id, item_id)] = {"actor_id": holder_id, "item_id": item_id,
		"believed_quantity": quantity, "confidence": 0.95, "evidence_tick": now_tick,
		"source_event_id": int(event.get("seq", -1)), "source": "WITNESSED_TRANSFER",
		"stale": quantity <= 0}
	observer["material_holder_beliefs"] = store

static func _mark_actor_beliefs_stale(observer: Dictionary, holder_id: String, now_tick: int) -> void:
	if holder_id.is_empty() or holder_id == String(observer.get("id", "")):
		return
	var store: Dictionary = observer.get("material_holder_beliefs", {})
	for key in store.keys():
		var belief: Dictionary = store[key]
		if String(belief.get("actor_id", "")) != holder_id:
			continue
		belief["stale"] = true
		belief["stale_tick"] = now_tick
		store[key] = belief
	observer["material_holder_beliefs"] = store

static func _key(actor_id: String, item_id: String) -> String:
	return "%s|%s" % [actor_id, item_id]

class_name AgencyMeasure
extends RefCounted
## P6.2-R2 ——测量基础设施（纯函数，无行为影响）。
## canonical_behavior_digest：**scoped digest**（明确非"逐位全状态"）——递归稳定 canonical
## （Dictionary key 排序、Array 保序、Vector2i/3i 与基础类型稳定编码）。
## 覆盖：RNG、事件（尾部 8 条 + 计数——性能取舍，非全事件等价证明）、world 行为相关量、
## 每 actor 的 tile/needs/physical/inventory/current_action/action_ticks_left/意图/spatial.hash_state/
## norms/open_questions/my_obligations/social_stance/grudges/visited_tiles 计数/tom.snapshot()/goal_manager.goals。
## 排除（详见报告）：life_history/sensitivities/personality（初始化后静态且不受 OFF/LIVE 影响）、
## last_decision_trace 全部（观察元数据）、agency 计数/缓存、_p5 埋点、memories/claims_received
## （体量大且假定仅经事件影响行为——若此假设错误则 digest 漏检，已列风险）。

const EVENT_TAIL := 8

static func digest_components(sim) -> Dictionary:
	var comps := {}
	comps["rng"] = str(sim._rng.state)
	comps["clock"] = "tick=%d seq=%d events=%d" % [sim.tick, sim._seq, sim.events.size()]
	var ev_tail: Array = []
	for e in sim.events.slice(maxi(0, sim.events.size() - EVENT_TAIL), sim.events.size()):
		ev_tail.append("%d|%s|%s|%d" % [int(e.get("seq", 0)), str(e.get("type", "")), str(e.get("actor_id", "")), int(e.get("tick", 0))])
	comps["events_tail"] = "|".join(ev_tail)
	comps["world"] = canon(_world_view(sim.world))
	var ids: Array = sim.actors.keys()
	ids.sort()
	for id in ids:
		comps["actor_" + str(id)] = canon(_actor_view(sim.actors[id]))
	comps["relationships"] = canon(sim.relationships.snapshot())
	comps["institutions"] = canon(sim.institutions)
	comps["obligations"] = canon(sim.obligations)
	return comps

static func canonical_behavior_digest(sim) -> String:
	var parts: Array = []
	var comps := digest_components(sim)
	var keys: Array = comps.keys()
	keys.sort()
	for k in keys:
		parts.append(str(k) + "=" + str(comps[k]))
	return str(hash("\n".join(parts)))

## 全部不等组件（按排序）——首分歧归因依据
static func diff_components(a_sim, b_sim) -> Array:
	var ca := digest_components(a_sim)
	var cb := digest_components(b_sim)
	var out: Array = []
	var keys: Array = ca.keys()
	keys.sort()
	for k in keys:
		if str(ca[k]) != str(cb.get(k, "<missing>")):
			out.append(str(k))
	return out

## 递归稳定 canonical
static func canon(v) -> String:
	match typeof(v):
		TYPE_DICTIONARY:
			var keys: Array = (v as Dictionary).keys()
			keys.sort()
			var out: Array = []
			for k in keys:
				out.append(canon(k) + ":" + canon((v as Dictionary)[k]))
			return "{" + ",".join(out) + "}"
		TYPE_ARRAY:
			var out2: Array = []
			for item in (v as Array):
				out2.append(canon(item))
			return "[" + ",".join(out2) + "]"
		TYPE_VECTOR2I:
			return "v2i(%d,%d)" % [(v as Vector2i).x, (v as Vector2i).y]
		TYPE_VECTOR3I:
			return "v3i(%d,%d,%d)" % [(v as Vector3i).x, (v as Vector3i).y, (v as Vector3i).z]
		TYPE_STRING:
			return "s(" + str(v) + ")"
		TYPE_INT, TYPE_FLOAT, TYPE_BOOL:
			return str(v)
		TYPE_NIL:
			return "null"
		TYPE_OBJECT:
			return "obj(" + str(v.get_class()) + ")"
	return "?" + str(typeof(v))

static func _world_view(w: Dictionary) -> Dictionary:
	var out := {}
	for k in ["is_night", "weather"]:
		out[k] = w.get(k, "")
	var berries: Array = []
	for b in w.get("berry_bushes", []):
		berries.append(str(b.get("pos", "")) + ":" + str(int(b.get("food", 0))))
	berries.sort()
	out["berry"] = berries
	var springs: Array = []
	for s2 in w.get("water_springs", []):
		springs.append(str(s2))
	springs.sort()
	out["springs"] = springs
	out["fires"] = w.get("fires", {}).size()
	out["shelters"] = w.get("shelters", {}).size()
	var wt: Dictionary = w.get("world_time", {})
	out["world_time"] = {"day": wt.get("day", 0), "hour": wt.get("hour", 0)}
	return out

static func _actor_view(a: Dictionary) -> Dictionary:
	var out := {}
	out["tile"] = a.get("tile", null)
	out["needs"] = a.get("needs", {})
	out["physical"] = a.get("physical", {})
	out["inventory"] = a.get("inventory", {})
	var cur = a.get("current_action", null)
	if typeof(cur) == TYPE_DICTIONARY:
		out["cur"] = {"action": cur.get("action", ""), "target": cur.get("target", null),
			"target_actor": cur.get("target_actor", ""), "ticks_left": a.get("action_ticks_left", 0)}
	else:
		out["cur"] = "null"
	var im = a.get("intentions", null)
	if im != null and im.has_intention():
		out["intent"] = {"action": im.current_intention.get("action", ""),
			"target": im.current_intention.get("target", null),
			"utility": im.current_intention.get("utility", 0.0)}
	else:
		out["intent"] = "none"
	var belief = a.get("spatial", null)
	if belief is SpatialBeliefMap:
		out["belief"] = (belief as SpatialBeliefMap).hash_state()
	else:
		out["belief"] = "-"
	out["norms"] = a.get("norms", {})
	out["open_questions"] = a.get("open_questions", [])
	out["my_obligations"] = a.get("my_obligations", [])
	out["social_stance"] = a.get("social_stance", {})
	out["grudges"] = a.get("grudges", {})
	var vt: Dictionary = a.get("visited_tiles", {})
	out["visited_n"] = vt.size()
	var tom = a.get("tom", null)
	if tom is TheoryOfMind:
		out["tom"] = canon(tom.snapshot())
	else:
		out["tom"] = "-"
	var gm = a.get("goal_manager", null)
	if gm is GoalManager:
		out["goals"] = canon(gm.goals)
	else:
		out["goals"] = "-"
	return out

## ── 漏斗采集（(actor_id, trace.tick) 去重；返回 true=首次采集该决策）──
static func collect_decision(trace: Dictionary, actor_id: String, seen: Dictionary, agg: Dictionary) -> bool:
	if not trace.has("agency_mode"):
		return false
	var dkey := actor_id + "|" + str(int(trace.get("tick", -1)))
	if seen.has(dkey):
		return false
	seen[dkey] = true
	var f: Dictionary = agg.get("funnel", {})
	var grounded: Array = trace.get("agency_grounded_candidates", [])
	f["actual_proposals"] = int(f.get("actual_proposals", 0)) + grounded.size() + (trace.get("agency_rejected_proposals", []) as Array).size()
	f["grounded"] = int(f.get("grounded", 0)) + grounded.size()
	f["grounded_already_considered"] = int(f.get("grounded_already_considered", 0)) + int(trace.get("agency_grounded_already_considered_count", 0))
	f["swapped_in"] = int(f.get("swapped_in", 0)) + (trace.get("agency_swapped_in_keys", []) as Array).size()
	for st in trace.get("agency_candidate_status", []):
		if str(st.get("status", "")) == "NOT_INSERTED":
			var r := str(st.get("reason", "?"))
			f["not_inserted_" + r] = int(f.get("not_inserted_" + r, 0)) + 1
	var sel = trace.get("agency_selected", null)
	if sel != null:
		f["selected_grounded"] = int(f.get("selected_grounded", 0)) + 1
	agg["funnel"] = f
	var rr: Dictionary = agg.get("reject_reasons", {})
	for rj in trace.get("agency_rejected_proposals", []):
		var rc := str(rj.get("reason_code", "?"))
		rr[rc] = int(rr.get(rc, 0)) + 1
	agg["reject_reasons"] = rr
	agg["inert_subgoals"] = int(agg.get("inert_subgoals", 0)) + (trace.get("agency_future_subgoals", []) as Array).size()
	var bp: Dictionary = agg.get("by_problem_action", {})
	for gc in grounded:
		var k2 := str(gc.get("problem_id", "?")) + "/" + str(gc.get("action", "?"))
		bp[k2] = int(bp.get(k2, 0)) + 1
	agg["by_problem_action"] = bp
	return true

## 原子写 JSON（tmp + rename）——pilot 自产数据文件，禁止人工复制
static func save_json_atomic(path: String, data) -> bool:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data))
	f.close()
	var d := DirAccess.open(path.get_base_dir())
	if d == null:
		return false
	if d.file_exists(path):
		d.remove(path)
	d.rename(tmp.get_file(), path.get_file())
	return true

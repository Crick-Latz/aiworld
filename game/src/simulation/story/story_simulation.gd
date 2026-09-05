class_name StorySimulation
extends RefCounted
## 故事模拟（OBS-02）：第一条不是预写剧本的因果闭环。
## 状态唯一拥有者；领域规则在 ResourceRules/HelpRules/KnowledgeStore（M07/M09/M10）。
## 命令经 submit_* 校验（幂等 by command_id；非法数量/ID/过期/远距拒绝且状态不变）。
## 因果链：lit_changed ← work_completed ← item_transferred ← help_accepted ← help_requested ← shortage_observed
## 决策唯一入口 HelpRules.decide_request——基准/对照夹具同规则，只有 reserve 不同。

var tick := 0
var actors: Dictionary = {}
var events: Array = []
var facts: Dictionary = {} # fact_id -> {statement, value}
var knowledge := KnowledgeStore.new()
var scenario: Dictionary
var lighthouse_lit := false
var consumed_fuel := 0
var work_completed_ticks := 0

var _seq := 0
var _map_query
var _receipts := {} # command_id -> receipt（幂等）
var _extra_requests: Array = [] # 对抗测试用的竞争请求（固定提交序执行）
var _departed := {} # id -> {reason_code, seq}（OBS-03）
var _delayed_messages: Array = [] # {deliver_tick, fact_id, to_id, source_seq, sent_cognition}（OBS-03）
var _message_delivered := {} # 去重键 -> true（OBS-03 幂等）
var _commitment_id := "" # 活跃承诺的幂等键（OBS-03：多次结算命令幂等）
var _inject_extra_done := false

func _init(map_query, scenario_data: Dictionary, spawn_tiles: Dictionary) -> void:
	_map_query = map_query
	scenario = scenario_data
	for f in scenario_data.get("facts", []):
		facts[f["id"]] = {"statement": f["statement"], "value": bool(f["initially_true"])}
	lighthouse_lit = bool(facts.get("fact_lighthouse_lit", {}).get("value", false))
	for a_cfg in scenario_data.get("actors", []):
		var id := str(a_cfg["id"])
		actors[id] = {
			"id": id,
			"role": str(a_cfg["role"]),
			"tile": spawn_tiles.get(id, Vector2i.ZERO),
			"prev_tile": spawn_tiles.get(id, Vector2i.ZERO),
			"inventory": (a_cfg["inventory"]).duplicate(),
			"reserve": (a_cfg["reserve"]).duplicate(),
			"phase": "idle",
			"activity": "待命",
			"path": [],
			"path_index": 0,
			"timer": 0,
			"goal": "",
			"goal_status": "",
			"display_name": _display_name_of(id),
		}
	# 请求者初始目标：先去灯塔查看（inspect 产生目标，不是开局自带）
	var req := _requester()
	if req != "":
		actors[req]["phase"] = "go_inspect"
		actors[req]["activity"] = "前往旧灯塔查看"
		actors[req]["goal"] = ""
	_set_path(req, _rules().get("work_target_poi", "old_lighthouse"))

func _display_name_of(id: String) -> String:
	var names := {"npc_weila": "薇拉", "npc_oun": "缄默者欧恩", "npc_kadga": "卡德加"}
	return names.get(id, id)

func _rules() -> Dictionary:
	return scenario.get("rules", {})

func _request() -> Dictionary:
	return scenario.get("story", {}).get("request", {})

func _requester() -> String:
	return str(_request().get("to_id", ""))

func _helper() -> String:
	return str(_request().get("from_id", ""))

func _item_display() -> String:
	return {"windcrystal_powder": "风晶粉末"}.get(str(_rules().get("fuel_item", "")), "材料")

# —— 命令入口（校验 + 幂等；拒绝时状态不变并返回稳定错误码）——

func submit_transfer(command_id: String, from_id: String, to_id: String, item: String, amount, issued_tick: int = -1, expires_tick: int = 2147483647) -> Dictionary:
	if _receipts.has(command_id):
		return _receipts[command_id] # 幂等：同 command_id 返回首张回执，不重复执行
	if issued_tick >= 0 and tick > expires_tick:
		var r0 := _reject(command_id, "E_PRECONDITION", "命令已过期")
		return r0
	var v: Dictionary = ResourceRules.validate_transfer(actors, from_id, to_id, item, amount, int(_rules().get("interact_range_tiles", 2)))
	if not v["ok"]:
		return _reject(command_id, str(v["code"]), str(v["message"]))
	var amount_i: int = int(amount)
	ResourceRules.apply_transfer(actors, from_id, to_id, item, amount_i)
	var receipt := {
		"command_id": command_id, "ok": true, "code": "OK",
		"effect": {"type": "item_transferred", "from": from_id, "to": to_id, "item": item, "amount": amount_i},
	}
	_receipts[command_id] = receipt
	var from_name: String = actors[from_id]["display_name"]
	var to_name: String = actors[to_id]["display_name"]
	var cause := knowledge.source_of(to_id, "fact_lighthouse_dark")
	_emit("item_transferred", from_id, "%s 将 %d 份%s 交给 %s" % [from_name, amount_i, _item_display(), to_name], cause,
		{"to_id": to_id, "item": item, "amount": amount_i})
	return receipt

func _reject(command_id: String, code: String, message: String) -> Dictionary:
	var receipt := {"command_id": command_id, "ok": false, "code": code, "message": message}
	_receipts[command_id] = receipt
	_emit("command_rejected", "", "命令被拒绝：%s" % message, -1, {"code": code, "command_id": command_id})
	return receipt

# —— 每 tick 行为（确定性；1 tick = 1 格）——

func step() -> Array:
	tick += 1
	var new_events: Array = []
	# —— 延迟消息投递（OBS-03）：内容捕获发送时认知，不投递时偷改 ——
	var still_pending: Array = []
	for msg in _delayed_messages:
		if int(msg["deliver_tick"]) <= tick:
			var key := "%s@%d@%s" % [str(msg["fact_id"]), int(msg["source_seq"]), str(msg["to_id"])]
			if not _message_delivered.has(key):
				_message_delivered[key] = true
				knowledge.learn(str(msg["to_id"]), str(msg["fact_id"]), int(msg["source_seq"]))
				_emit("message_delivered", str(msg["to_id"]),
					"%s 收到了迟来的消息：%s" % [actors.get(msg["to_id"], {}).get("display_name", str(msg["to_id"])), facts.get(msg["fact_id"], {}).get("statement", "")],
					int(msg["source_seq"]), {"fact_id": msg["fact_id"]})
		else:
			still_pending.append(msg)
	_delayed_messages = still_pending
	# —— 行为 tick ——
	for id in _ordered_ids():
		if _departed.has(id):
			continue
		var a: Dictionary = actors[id]
		a["prev_tile"] = a["tile"]
		_tick_actor(id, a)
	for e in events:
		if int(e["tick"]) == tick:
			new_events.append(e)
	return new_events

# —— 外部事件入口（OBS-03）——

## 人物离场：失效其计划/请求/承诺；其他持有人可重新计划（有 reason_code/cause_seq）
func inject_actor_departed(actor_id: String, reason_code: String = "left_world") -> Dictionary:
	if not actors.has(actor_id) or _departed.has(actor_id):
		return {"ok": false, "code": "E_PRECONDITION", "message": "角色不存在或已离场"}
	var seq := _emit("actor_departed", actor_id,
		"%s 离开了灰雾港（%s）" % [actors[actor_id]["display_name"], reason_code], -1,
		{"reason_code": reason_code})
	_departed[actor_id] = {"reason_code": reason_code, "seq": seq}
	var a: Dictionary = actors[actor_id]
	if a["phase"] != "done":
		a["goal_status"] = "abandoned"
	# 失效活跃承诺：供应者或需求者离场都取消
	if help_request_active:
		var req := _request()
		if str(req.get("from_id", "")) == actor_id or str(req.get("to_id", "")) == actor_id:
			_cancel_commitment("supplier_departed" if str(req.get("from_id", "")) == actor_id else "requester_departed", seq)
	# 已满足目标不重开（lit=true 则不再索取）
	if not lighthouse_lit:
		_try_replan(seq)
	return {"ok": true, "code": "OK", "seq": seq, "message": ""}

## 延迟消息：deliver_tick 到达时才让 to_id 知道 fact_id（内容为发送时认知）
func schedule_delayed_message(deliver_tick: int, fact_id: String, to_id: String, source_seq: int, sent_cognition: String) -> void:
	_delayed_messages.append({
		"deliver_tick": deliver_tick, "fact_id": fact_id, "to_id": to_id,
		"source_seq": source_seq, "sent_cognition": sent_cognition,
	})

var help_request_active := false

func _cancel_commitment(reason_code: String, cause_seq: int) -> void:
	var req := _request()
	if not help_request_active:
		return
	help_request_active = false
	var other := str(req.get("to_id", "")) if reason_code == "supplier_departed" else str(req.get("from_id", ""))
	var other_name: String = actors.get(other, {}).get("display_name", other)
	_emit("commitment_cancelled", str(req.get("from_id", "")),
		"承诺取消（%s）——%s 的交接不再执行" % [reason_code, other_name], cause_seq,
		{"reason_code": reason_code})
	# 已转移物品留在实际持有人；尚未转移的不扣
	var to_a: Dictionary = actors.get(str(req.get("to_id", "")), {})
	if to_a.get("phase", "") == "waiting_delivery":
		to_a["phase"] = "goal_failed"
		to_a["goal_status"] = "waiting"

## 计划替换（OBS-03 规则 4）：目标未完成且持有人在场时找别的知情材料持有人；
## 原目标拥有者离场 → 只有另一位在场、已知短缺、有合法恢复目标的 NPC 才产生自己的新请求。
func _try_replan(cause_seq: int) -> void:
	if lighthouse_lit:
		return
	var req := _request()
	var original_requester := str(req.get("to_id", ""))
	var original_helper := str(req.get("from_id", ""))
	# 候选：在场、有库存、有恢复目标（或原请求者不在场时由知情者接棒）
	for id in _ordered_ids():
		if _departed.has(id) or not actors.has(id):
			continue
		var a: Dictionary = actors[id]
		if id == original_helper and _departed.has(original_helper):
			continue
		if a["phase"] != "goal_failed" and a["phase"] != "idle":
			continue
		var item := str(req.get("item", ""))
		var have: int = int(a["inventory"].get(item, 0))
		if have <= 0:
			continue
		if not knowledge.knows(id, "fact_lighthouse_dark") and id != original_requester:
			continue # 未知情者不能无来源接棒
		# 生成独立的新请求：由这位知情持有人向另一位需求者提供
		var target_id := original_requester if not _departed.has(original_requester) and original_requester != id else ""
		if target_id == "":
			continue
		_emit("plan_replaced", id,
			"%s 接手了恢复灯塔的计划" % a["display_name"], cause_seq,
			{"reason_code": "replan_after_departure"})
		a["phase"] = "go_deliver"
		a["activity"] = "接手交付材料"
		a["_deliver_to"] = target_id
		a["_deliver_acc_seq"] = cause_seq
		_set_path(id, "", actors[target_id]["tile"])
		actors[target_id]["phase"] = "waiting_delivery"
		help_request_active = true
		return
	# 无合格继任：记录目标不能继续的原因
	_emit("goal_terminated", "", "没有在场且知情的材料持有人，恢复灯塔目标终止", cause_seq,
		{"reason_code": "no_successor"})

func _ordered_ids() -> Array:
	var ids := actors.keys()
	ids.sort()
	return ids

func _tick_actor(id: String, a: Dictionary) -> void:
	match a["phase"]:
		"go_inspect":
			if _advance(a):
				a["phase"] = "inspecting"
				a["timer"] = 2
				a["activity"] = "查看灯塔"
		"inspecting":
			a["timer"] = int(a["timer"]) - 1
			if a["timer"] <= 0:
				var seq := _emit("shortage_observed", id, "%s 发现旧灯塔缺少燃料" % a["display_name"], -1, {})
				knowledge.learn(id, "fact_lighthouse_dark", seq)
				a["goal"] = "restore_lighthouse"
				a["goal_status"] = "active"
				_start_request(id, seq)
		"waiting_delivery":
			a["activity"] = "等待材料"
		"go_work":
			if _advance(a):
				a["phase"] = "working"
				a["timer"] = int(_rules().get("work_ticks", 3))
				a["activity"] = "点亮灯塔"
		"working":
			a["timer"] = int(a["timer"]) - 1
			if a["timer"] <= 0:
				_complete_work(id, a)
		"goal_failed":
			a["activity"] = "目标受阻：%s" % a["goal"]
		"done":
			a["activity"] = "完成"
		"go_deliver":
			if _advance(a):
				_execute_delivery(id, a)
		_:
			a["activity"] = "留守" # idle / bystandander

func _start_request(requester_id: String, cause_seq: int) -> void:
	var req := _request()
	var helper_id := str(req["from_id"])
	var h: Dictionary = actors[helper_id]
	var item := str(req["item"])
	var amount: int = int(req["amount"])
	_emit("help_requested", requester_id,
		"%s 向 %s 请求 %d 份%s（原因：%s）" % [actors[requester_id]["display_name"], h["display_name"], amount, _item_display(), str(req["reason"])],
		cause_seq, {"from_id": helper_id, "item": item, "amount": amount})
	knowledge.learn(helper_id, "fact_lighthouse_dark", cause_seq) # 请求本身传递了短缺信息
	# 唯一决策点：同一规则处理两份夹具
	help_request_active = true
	var inv: int = int(h["inventory"].get(item, 0))
	var res: int = int(h["reserve"].get(item, 0))
	var decision: Dictionary = HelpRules.decide_request(inv, res, amount, h["display_name"], item)
	if decision["decision"] == "accept":
		var acc_seq := _emit("help_accepted", helper_id,
			"%s 同意帮忙——%s" % [h["display_name"], decision["reason_text"]], _last_seq(), {"to_id": requester_id})
		h["phase"] = "go_deliver"
		h["activity"] = "给薇拉送材料"
		_set_path(helper_id, "", actors[requester_id]["tile"])
		actors[requester_id]["phase"] = "waiting_delivery"
		h["_deliver_to"] = requester_id
		h["_deliver_acc_seq"] = acc_seq
	else:
		_emit("help_declined", helper_id,
			"%s 拒绝了请求——%s" % [h["display_name"], decision["reason_text"]], _last_seq(), {"to_id": requester_id})
		actors[requester_id]["phase"] = "goal_failed"
		actors[requester_id]["goal_status"] = "waiting" # 不刷重复请求

func _execute_delivery(helper_id: String, h: Dictionary) -> void:
	var to_id := str(h.get("_deliver_to", ""))
	# 执行节点再核验（OBS-03 规则 3）：防止消息没送达时继续和离场者交易
	if _departed.has(helper_id) or _departed.has(to_id):
		_cancel_commitment("party_departed", _departed.get(helper_id, _departed.get(to_id, {})).get("seq", -1))
		return
	var item := str(_request()["item"])
	var amount: int = int(_request()["amount"])
	var v: Dictionary = ResourceRules.validate_transfer(actors, helper_id, to_id, item, amount, int(_rules().get("interact_range_tiles", 2)))
	if not v["ok"]: # 接受不等于转移：执行时再校验（双方在世/距离/库存）
		_emit("command_rejected", helper_id, "交接失败：%s" % v["message"], -1, {"code": v["code"]})
		actors[to_id]["phase"] = "goal_failed"
		h["phase"] = "idle"
		return
	ResourceRules.apply_transfer(actors, helper_id, to_id, item, amount)
	_emit("item_transferred", helper_id,
		"%s 将 %d 份%s 交给 %s" % [h["display_name"], amount, _item_display(), actors[to_id]["display_name"]],
		int(h.get("_deliver_acc_seq", -1)), {"to_id": to_id, "item": item, "amount": amount})
	h["phase"] = "idle"
	h["activity"] = "已交付"
	actors[to_id]["phase"] = "go_work"
	actors[to_id]["activity"] = "前往灯塔点火"
	_set_path(to_id, str(_rules().get("work_target_poi", "")))

func _complete_work(id: String, a: Dictionary) -> void:
	var item := str(_rules().get("fuel_item", ""))
	var needed: int = int(_rules().get("fuel_needed", 2))
	var v: Dictionary = ResourceRules.validate_work(a, _poi_tile(), item, needed, int(_rules().get("interact_range_tiles", 2)))
	if not v["ok"]:
		a["phase"] = "goal_failed"
		_emit("command_rejected", id, "工作失败：%s" % v["message"], -1, {"code": v["code"]})
		return
	ResourceRules.consume(a, item, needed)
	consumed_fuel += needed
	work_completed_ticks = int(_rules().get("work_ticks", 3))
	var work_seq := _emit("work_completed", id, "%s 消耗 %d 份%s 完成灯塔工作" % [a["display_name"], needed, _item_display()],
		_last_type_seq("item_transferred"), {"consumed": needed})
	lighthouse_lit = true
	facts["fact_lighthouse_lit"]["value"] = true
	facts["fact_lighthouse_dark"]["value"] = false
	_emit("lit_changed", id, "旧灯塔重新点亮了", work_seq, {"lit": true})
	a["phase"] = "done"
	a["goal_status"] = "succeeded"
	a["activity"] = "灯塔已点亮"

# —— 工具 ——

func _set_path(id: String, poi_id: String, target_tile := Vector2i(-1, -1)) -> void:
	var dest := target_tile
	if dest.x < 0 and poi_id != "":
		dest = _map_query.get_poi_tile(poi_id)
	var a: Dictionary = actors[id]
	var path: Array = _map_query.find_walk_path(Vector3i(a["tile"].x, 0, a["tile"].y), Vector3i(dest.x, 0, dest.y))
	a["path"] = path
	a["path_index"] = 1

func _advance(a: Dictionary) -> bool:
	var path: Array = a["path"]
	if int(a["path_index"]) < path.size():
		var cell: Vector2i = path[int(a["path_index"])]
		a["tile"] = cell
		a["path_index"] = int(a["path_index"]) + 1
	return int(a["path_index"]) >= path.size()

func _poi_tile() -> Vector2i:
	return _map_query.get_poi_tile(str(_rules().get("work_target_poi", "")))

func _emit(type: String, actor_id: String, text: String, cause_seq: int, extra: Dictionary) -> int:
	var e := {
		"seq": _seq, "tick": tick, "type": type, "actor_id": actor_id,
		"text": text, "cause_seq": cause_seq,
	}
	for k in extra:
		e[k] = extra[k]
	_seq += 1
	events.append(e)
	return int(e["seq"])

func _last_seq() -> int:
	return _seq - 1

func _last_type_seq(type: String) -> int:
	for i in range(events.size() - 1, -1, -1):
		if events[i]["type"] == type:
			return int(events[i]["seq"])
	return -1

# 因果链提取：从某事件回溯 cause_seq 链
func causal_chain_of(type: String) -> Array:
	var target := -1
	for e in events:
		if e["type"] == type:
			target = int(e["seq"])
	var chain: Array = []
	while target >= 0:
		for e in events:
			if int(e["seq"]) == target:
				chain.push_front(str(e["type"]))
				target = int(e["cause_seq"])
	return chain

func get_snapshot() -> Dictionary:
	var out := {"tick": tick, "lighthouse_lit": lighthouse_lit, "consumed_fuel": consumed_fuel, "actors": {}}
	for id in _ordered_ids():
		var a: Dictionary = actors[id]
		out["actors"][id] = {
			"tile": a["tile"], "prev_tile": a["prev_tile"], "phase": a["phase"],
			"activity": a["activity"], "inventory": (a["inventory"]).duplicate(),
			"goal": a["goal"], "goal_status": a["goal_status"],
		}
	return out

func event_summary() -> String:
	var parts: Array = []
	for e in events:
		parts.append("%d:%d:%s:%s" % [e["seq"], e["tick"], e["type"], e["actor_id"]])
	return "\n".join(parts)

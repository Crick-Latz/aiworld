extends SceneTree
## P2.1 野外制度生命周期扫描（GPT 第 15-18 条）：
## 多 seed、长时程、正常行为系统、零剧本干预。不以 rules_adopted>=N 为成功——
## 验证 A：完整链（regularity→proposal→stance→institution→compliance→response）能否无脚本走完
## 验证 B：不同 seed 是否出现不同结局（motif 分类）
var _s := false
var _f := false
func _initialize() -> void: pass
func _process(_d: float) -> bool:
	if not _s: _s = true; _run()
	return _f
func _run() -> void:
	var ps: PackedScene = load("res://scenes/observer/observer_main.tscn")
	var inst = ps.instantiate()
	root.add_child(inst)
	for i in 20: await physics_frame
	var mq = inst.get_node("World/MapController")
	var scenario: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/deserted_island_v2.json"))
	var spot = mq.get_poi_tile("post_house")
	var configs: Array = []
	for ac in scenario.get("actors", []):
		var cfg = ac.duplicate()
		cfg["spawn"] = spot
		configs.append(cfg)
	var lifecycle := {}
	var motifs := {}
	var full_chain_seeds := 0
	for s2 in range(40001, 40031):
		var sim := IslandSimulation.new(mq, s2, configs)
		for i in 900:
			sim.step()
		var c := {}
		for e in sim.events:
			var t := str(e["type"])
			if ["rule_proposed","rule_supported","rule_opposed","institution_established","storage_contributed","storage_withheld","confronted_violation","rule_revised","relocated","promise_made","promise_kept"].has(t):
				c[t] = int(c.get(t, 0)) + 1
				lifecycle[t] = int(lifecycle.get(t, 0)) + 1
		# motif 分类（第 18 条）
		var motif := "NO_INSTITUTION"
		if c.get("institution_established", 0) > 0:
			if c.get("confronted_violation", 0) > 0 and c.get("storage_withheld", 0) > 0:
				motif = "RULE_WITH_ENFORCEMENT"
			elif c.get("storage_withheld", 0) > 0:
				motif = "RULE_WITH_HIDDEN_CHEATING"
			elif c.get("storage_contributed", 0) > 0:
				motif = "RULE_STABILIZED"
			else:
				motif = "RULE_INACTIVE"
		elif c.get("rule_proposed", 0) > 0:
			motif = "PROPOSAL_REJECTED"
		motifs[motif] = int(motifs.get(motif, 0)) + 1
		# 完整链：regularity(约定存在)→提议→建立→合规或违规→社会回应
		if c.get("rule_proposed", 0) > 0 and c.get("institution_established", 0) > 0:
			if c.get("storage_contributed", 0) > 0 or c.get("storage_withheld", 0) > 0:
				full_chain_seeds += 1
		# institutions 客观记录
		if sim.institutions.size() > 0:
			lifecycle["institution_records"] = int(lifecycle.get("institution_records", 0)) + sim.institutions.size()
	print("P21_LIFECYCLE %s" % str(lifecycle))
	print("P21_MOTIFS %s" % str(motifs))
	print("P21_FULL_CHAIN %d/30" % full_chain_seeds)
	_f = true
	quit(0)

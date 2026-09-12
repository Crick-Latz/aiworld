class_name LlmNarrativeRenderer
extends RefCounted
## P3a-3 真实 LLM Renderer（最小权限契约）：
##   输入：claim package（已验证的原子主张 + 视角 + 禁止推断）——不给 EventLog/WorldState
##   输出：{sentences: [{text, claim_ids}]}——系统从 claim_ids 派生全部底层 ids
##   LLM 权限：READ ONLY Surface Renderer。不能创建 claim、不能引用 claim_ids 之外的
##   任何事实、不能编造对话（IR 无 speech 时 Validator 拒引号）。
##
## 第一版只测 fidelity：neutral_chronicle 风格、低 temperature、单一中文。
## 断网/超时/残缺 → NarrativeRenderer 自动 fallback Template，模拟继续运行。
##
## 配置（game/config/ai.local.json，被 .gitignore 排除；或环境变量）：
##   {"base_url": "...", "api_key": "...", "model": "..."}
##   未配置 → render 直接返回 null（走 fallback），零网络。

const PROMPT_SYSTEM := "你是一个编年史渲染器（Grounded Narrative Renderer），不是故事生成器。\n" \
	+ "你会收到若干条已验证的原子主张（claims），每条有唯一 claim_id、主体、谓语和认识层级。\n" \
	+ "你的唯一任务：把其中部分主张组合成 1-3 句自然的中文编年史句子。\n" \
	+ "硬性禁止：\n" \
	+ "- 不得引入任何主张之外的事实、动机、情绪、对话或因果关系\n" \
	+ "- 不得使用引号对话\n" \
	+ "- 不得添加『因为/所以/于是』等因果连接，除非主张本身是 CAUSAL_LINK 类型\n" \
	+ "- 主张不足以支撑的内容必须省略，不得补全\n" \
	+ "- 认识层级必须保持：BELIEVED/PERCEIVED 的主张只能写成『某人认为/看见』，不能写成客观事实\n" \
	+ "输出格式（严格 JSON）：\n" \
	+ '{"sentences": [{"text": "句子", "claim_ids": ["C0"]}]}'

static func make_provider(config: Dictionary) -> Dictionary:
	# 返回 {render: Callable}——与 Template/Mock 同一契约
	return {"render": func(ir: Dictionary, style: String, language: String, length: int):
		return await LlmNarrativeRenderer.render(config, ir, style, language, length)}

## 主入口：构建 claim package → 调 API → 解析 → 转标准输出（ids 由系统派生）
static func render(config: Dictionary, ir: Dictionary, _style: String, _language: String, length: int):
	if not bool(ir.get("ok", false)):
		return null  # IR 无效 → 上层 fallback
	if config.is_empty() or not config.has("base_url") or not config.has("api_key"):
		return null  # 未配置 → fallback（零网络）
	var package := _build_claim_package(ir, maxi(1, length))
	if package.is_empty():
		return null  # 无可叙 claims → fallback（template 会写"无事可记"）
	var raw_text: String = await _call_api(config, package)
	if raw_text == "":
		return null  # 网络失败/超时 → fallback
	var parsed := _parse_response(raw_text, ir)
	if parsed.is_empty():
		return null  # 残缺/幻觉 → fallback
	return parsed

## ── Claim Package：LLM 看到的全部信息（不含 EventLog/WorldState/原始事件文本）──
static func _build_claim_package(ir: Dictionary, max_sentences: int) -> Array:
	var claims: Array = ir.get("claims", [])
	var beats: Array = ir.get("selected_beats", [])
	var beat_claims := {}
	for b in beats:
		beat_claims[str(b.get("beat_id", ""))] = b.get("claim_ids", [])
	# P3c-0：IR 携带 actor_names（display name）——claim package 的 subject 用人名
	var name_map: Dictionary = ir.get("actor_names", {})
	var out: Array = []
	for c in claims:
		if c.get("beat_id", "") == "":
			continue  # 只发已被 beat 选中的主张（叙事显著的）
		var subj_raw := str(c.get("subject", ""))
		out.append({
			"claim_id": str(c.get("claim_id", "")),
			"subject": name_map.get(subj_raw, subj_raw),
			"predicate": str(c.get("predicate", "")),
			"object": c.get("object", {}),
			"epistemic_status": str(c.get("epistemic_status", "OBJECTIVE")),
			"tick_hint": _tick_of_claim(ir, c),
		})
	if out.is_empty():
		return []
	return [{"max_sentences": max_sentences, "perspective": str(ir.get("perspective", "OBJECTIVE")),
		"claims": out}]

static func _tick_of_claim(ir: Dictionary, c: Dictionary) -> int:
	for f in ir.get("known_facts", []):
		if (c.get("source_event_ids", []) as Array).has(int(f.get("seq", -1))):
			return int(f.get("tick", 0))
	return 0

## ── API 调用（OpenAI 兼容 /chat/completions；同步阻塞版——渲染离主循环，可接受）──
static func _call_api(config: Dictionary, package: Array) -> String:
	var http := HTTPRequest.new()
	http.timeout = float(config.get("timeout_seconds", 8))
	# 临时节点挂树（headless 下 SceneTree.root 可用）；用完即毁
	var tree := Engine.get_main_loop()
	if tree is SceneTree:
		(tree as SceneTree).root.add_child(http)
	var body := JSON.stringify({
		"model": str(config.get("model", "glm-4-flash")),
		"temperature": 0.2,
		"messages": [
			{"role": "system", "content": PROMPT_SYSTEM},
			{"role": "user", "content": JSON.stringify(package)},
		],
	})
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer " + str(config["api_key"]),
	])
	var url := str(config["base_url"]).rstrip("/") + "/chat/completions"
	var err := http.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		if http.get_parent():
			http.queue_free()
		return ""
	var result: Array = await http.request_completed
	if http.get_parent():
		http.queue_free()
	if result.size() < 4 or int(result[1]) != 200:
		return ""
	var json: Variant = JSON.parse_string(str(result[3].get_string_from_utf8()))
	if typeof(json) != TYPE_DICTIONARY:
		return ""
	var choices: Array = json.get("choices", [])
	if choices.is_empty():
		return ""
	return str(choices[0].get("message", {}).get("content", ""))

## ── 解析：LLM 只允许 {sentences:[{text, claim_ids}]}；ids 系统派生 ──
static func _parse_response(raw: String, ir: Dictionary) -> Dictionary:
	var json_text := raw.strip_edges()
	# 容错：模型可能包 markdown 代码块
	if json_text.begins_with("```"):
		json_text = json_text.substr(json_text.find("\n") + 1)
		json_text = json_text.replace("```", "")
	var parsed: Variant = JSON.parse_string(json_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var sentences_raw: Array = parsed.get("sentences", [])
	if sentences_raw.is_empty():
		return {}
	var ir_claims: Array = ir.get("claims", [])
	var valid_cids := {}
	for c in ir_claims:
		valid_cids[str(c.get("claim_id", ""))] = true
	var sentences: Array = []
	var sid := 0
	for sn in sentences_raw:
		if typeof(sn) != TYPE_DICTIONARY:
			continue
		var text := str(sn.get("text", "")).strip_edges()
		var cids: Array = sn.get("claim_ids", [])
		# 最小权限：LLM 引用的 claim_ids 必须全部在 IR 中（幻觉 id 剔除整句）
		var all_valid := true
		for cid in cids:
			if not valid_cids.has(str(cid)):
				all_valid = false
				break
		if text == "" or cids.is_empty() or not all_valid:
			continue
		# ids 由系统从 claim_ids 派生（LLM 无权输出底层 ids）
		var derived: Dictionary = NarrativeClaim.derive_sources(ir_claims, cids)
		sentences.append({"sentence_id": "S%d" % sid, "kind": "CONTENT", "text": text,
			"claim_ids": cids, "beat_ids": _beats_of_claims(ir, cids),
			"source_event_ids": derived["event_ids"], "source_trace_ids": derived["trace_ids"]})
		sid += 1
	if sentences.is_empty():
		return {}
	return {"ok": true, "text": "\n".join((sentences.map(func(s): return str(s["text"])) as Array)),
		"sentences": sentences,
		"beat_ids": _collect(sentences, "beat_ids"),
		"source_event_ids": _collect(sentences, "source_event_ids"),
		"source_trace_ids": _collect(sentences, "source_trace_ids"),
		"renderer": "llm", "schema_version": "narrative-output-1.1"}

static func _beats_of_claims(ir: Dictionary, cids: Array) -> Array:
	var out: Array = []
	for b in ir.get("selected_beats", []):
		for cid in cids:
			if (b.get("claim_ids", []) as Array).has(str(cid)):
				if not out.has(str(b.get("beat_id", ""))):
					out.append(str(b.get("beat_id", "")))
	return out

static func _collect(sentences: Array, field: String) -> Array:
	var out: Array = []
	for sn in sentences:
		for v in sn.get(field, []):
			if not out.has(v):
				out.append(v)
	return out

## 配置加载：ai.local.json > 环境变量（AIWORLD_LLM_BASE_URL/AIWORLD_LLM_API_KEY/AIWORLD_LLM_MODEL）
static func load_config() -> Dictionary:
	var path := "res://config/ai.local.json"
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) == TYPE_DICTIONARY and parsed.has("api_key"):
			return parsed
	var base := OS.get_environment("AIWORLD_LLM_BASE_URL")
	var key := OS.get_environment("AIWORLD_LLM_API_KEY")
	if base != "" and key != "":
		return {"base_url": base, "api_key": key, "model": OS.get_environment("AIWORLD_LLM_MODEL")}
	return {}

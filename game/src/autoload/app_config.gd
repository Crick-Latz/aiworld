extends Node
## AppConfig：运行时配置（WP-02 / R1）。
## 纪律：配置是数据——先读 defaults，local 存在时只做"已存在键 + 同类型"的受控覆盖；
## 不允许配置执行代码、充当文件路径或注入新结构；文件缺失/JSON 非法返回稳定错误。
## R1：JSON 解析改用 JSON.new().parse()（安静，不向 stderr 打引擎 ERROR）；
## 失败信息走 print（stdout），不用 push_error 污染 stderr。

const DEFAULTS_PATH := "res://config/runtime.defaults.json"
const LOCAL_PATH := "res://config/runtime.local.json"
const VALID_MODES := ["demo", "mock_ai", "live_ai"]

signal config_ready
signal config_error(code: String, message: String)

var mode := "demo"
var live_ai := false
var raw: Dictionary = {}
var last_error_code := ""
var last_error_message := ""

func _ready() -> void:
	var result := load_config()
	if result.ok:
		raw = result.data
		mode = str(raw.get("mode", "demo"))
		var features = raw.get("features", {})
		live_ai = bool(features.get("live_ai", false)) if typeof(features) == TYPE_DICTIONARY else false
		config_ready.emit()
	else:
		last_error_code = str(result.code)
		last_error_message = str(result.message)
		print("AppConfig: %s: %s" % [last_error_code, last_error_message])
		config_error.emit(last_error_code, last_error_message)

func load_config() -> Dictionary:
	var defaults := _read_json(DEFAULTS_PATH)
	if not defaults.ok:
		return defaults
	var merged: Dictionary = defaults.data.duplicate(true)
	if FileAccess.file_exists(LOCAL_PATH):
		var local := _read_json(LOCAL_PATH)
		if not local.ok:
			return local
		_overlay_controlled(merged, local.data)
	var mode_check := _validate_mode(merged)
	if not mode_check.ok:
		return mode_check
	return {"ok": true, "code": "OK", "message": "", "data": merged}

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "code": "E_DATA_MISSING", "message": "找不到配置文件：" + path, "data": {}}
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {"ok": false, "code": "E_JSON_INVALID", "message": "配置文件为空或不可读：" + path, "data": {}}
	var parser := JSON.new()
	if parser.parse(text) != OK:
		var reason := str(parser.get_error_message()).replace("\n", " ").strip_edges()
		if reason.length() > 100:
			reason = reason.substr(0, 100)
		return {"ok": false, "code": "E_JSON_INVALID", "message": "配置 JSON 解析失败（第 %d 行）：%s" % [parser.get_error_line(), reason], "data": {}}
	if typeof(parser.data) != TYPE_DICTIONARY:
		return {"ok": false, "code": "E_JSON_INVALID", "message": "配置不是 JSON 对象：" + path, "data": {}}
	return {"ok": true, "code": "OK", "message": "", "data": parser.data}

# 受控覆盖：只允许覆盖 defaults 中已存在且类型一致的键，递归合并 Dictionary
func _overlay_controlled(base: Dictionary, over: Dictionary) -> void:
	for k in over:
		if not base.has(k):
			continue
		var bv = base[k]
		var ov = over[k]
		if typeof(bv) == TYPE_DICTIONARY and typeof(ov) == TYPE_DICTIONARY:
			_overlay_controlled(bv, ov)
		elif typeof(bv) == typeof(ov):
			base[k] = ov

func _validate_mode(cfg: Dictionary) -> Dictionary:
	var m = cfg.get("mode", "demo")
	if not VALID_MODES.has(str(m)):
		return {"ok": false, "code": "E_SCHEMA_INVALID", "message": "mode 必须是 demo/mock_ai/live_ai，当前为：" + str(m), "data": {}}
	return {"ok": true, "code": "OK", "message": "", "data": cfg}

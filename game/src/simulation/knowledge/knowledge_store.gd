class_name KnowledgeStore
extends RefCounted
## 感知与知识（OBS-02，M10）：谁通过什么事件知道了什么事实。
## 未 inspect 的角色不能无来源知道库存短缺——知识只来自已发生的事件。

var _known := {} # actor_id -> {fact_id -> source_event_seq}

func learn(actor_id: String, fact_id: String, source_seq: int) -> void:
	if not _known.has(actor_id):
		_known[actor_id] = {}
	_known[actor_id][fact_id] = source_seq

func knows(actor_id: String, fact_id: String) -> bool:
	return _known.has(actor_id) and _known[actor_id].has(fact_id)

func source_of(actor_id: String, fact_id: String) -> int:
	if knows(actor_id, fact_id):
		return int(_known[actor_id][fact_id])
	return -1

func facts_known_by(actor_id: String) -> Dictionary:
	return _known.get(actor_id, {}).duplicate()

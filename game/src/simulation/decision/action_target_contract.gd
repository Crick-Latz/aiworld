class_name ActionTargetContract
extends RefCounted
## Resource-target metadata and subjective invalidation checks.
##
## The action records which key in actor.known_resources justified its target.
## Runtime cancellation may use only that actor-facing knowledge view. Missing
## knowledge is UNKNOWN and never treated as evidence that the resource vanished.

const SOURCE_KEY_FIELD := "target_source_key"

static func with_source(action: Dictionary, source_key: String) -> Dictionary:
	var out := action.duplicate(true)
	out[SOURCE_KEY_FIELD] = source_key
	return out

static func is_disconfirmed(action: Dictionary, known_resources: Dictionary) -> bool:
	if typeof(action.get(SOURCE_KEY_FIELD)) != TYPE_STRING:
		return false
	var source_key := str(action[SOURCE_KEY_FIELD])
	var target = action.get("target", null)
	if source_key == "" or typeof(target) != TYPE_VECTOR2I:
		return false
	# A missing/malformed knowledge channel is not negative evidence.
	if not known_resources.has(source_key) or typeof(known_resources[source_key]) != TYPE_ARRAY:
		return false
	return not (known_resources[source_key] as Array).has(target)

class_name RecipeKnowledgeAdapter
extends RefCounted
## P6.3A-R1 §5——knowledge 侧的配方知识适配器。
## 依赖方向：knowledge adapter → items(RecipeCatalog) → shared(CapabilitySpec)。
## items/ 模块不再依赖 WorldKnowledgeStore（循环消除）。

static func known_recipe_refs(expertise_tags: Array, store: WorldKnowledgeStore, catalog: RecipeCatalog) -> Array:
	var available: Dictionary = store.available_for(expertise_tags)
	var known_facts: Dictionary = available.get("facts", {})
	var out: Array = []
	for rid in catalog.all_ids_sorted():
		var recipe: Dictionary = catalog.spec(str(rid))
		var all_known := true
		for kref in recipe.get("knowledge_refs", []):
			if not known_facts.has(str(kref)):
				all_known = false
				break
		if all_known:
			out.append(str(rid))
	return out

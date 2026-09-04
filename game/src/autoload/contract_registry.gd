extends Node
## ContractRegistry：契约入口（WP-02）。
## Godot 端不实现完整 JSON Schema——版本、必填字段、ID/引用/权重/敏感字段规则
## 统一由 WorldSpecLoader.validate 提供单一实现，此处作为 Autoload 服务暴露给运行时。

func spec_schema_version() -> String:
	return "0.1"

func validate_world_spec(spec) -> Dictionary:
	return WorldSpecLoader.validate(spec)

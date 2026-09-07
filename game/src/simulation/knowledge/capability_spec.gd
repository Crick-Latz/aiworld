class_name CapabilitySpec
extends RefCounted
## P6.0 §9 Capability Ontology——能力不是行动。
## CUT 可由 knife / sharp stone / axe 提供；同一能力可有多个来源。
## 能力域（domain）用于和 LifeHistory 派生的 expertise 匹配（数据驱动，无角色名分支）。

const CAPABILITIES := {
	"CUT": {"domain": "CRAFT", "desc": "切割材料"},
	"PIERCE": {"domain": "CRAFT", "desc": "穿刺"},
	"STRIKE": {"domain": "CRAFT", "desc": "敲击"},
	"DIG": {"domain": "CRAFT", "desc": "挖掘"},
	"BIND": {"domain": "CRAFT", "desc": "捆扎连接"},
	"CARRY": {"domain": "LOGISTIC", "desc": "搬运"},
	"CONTAIN": {"domain": "LOGISTIC", "desc": "容纳储存"},
	"COOK": {"domain": "FOOD", "desc": "烹饪"},
	"PRESERVE": {"domain": "FOOD", "desc": "保存食物"},
	"HUNT_SMALL": {"domain": "HUNT", "desc": "捕猎小型猎物"},
	"HUNT_MEDIUM": {"domain": "HUNT", "desc": "捕猎中型猎物"},
	"FISH": {"domain": "HUNT", "desc": "捕鱼"},
	"TRAP": {"domain": "HUNT", "desc": "设陷阱"},
	"BUILD_BASIC": {"domain": "CONSTRUCTION", "desc": "基础建造"},
	"BUILD_STRONG": {"domain": "CONSTRUCTION", "desc": "坚固建造"},
	"LIGHT": {"domain": "FIRE", "desc": "生火照明"},
	"HEAT": {"domain": "FIRE", "desc": "取暖"},
	"DEFEND": {"domain": "COMBAT", "desc": "防卫"},
	"THREATEN": {"domain": "COMBAT", "desc": "威慑"},
	"NAVIGATE": {"domain": "NAVIGATION", "desc": "导航航行"},
	"WATER_TRANSPORT": {"domain": "NAVIGATION", "desc": "水上载具移动"},
	"STORE": {"domain": "LOGISTIC", "desc": "长期储藏"},
	"TRADE": {"domain": "SOCIAL", "desc": "交换"},
	"COOPERATE_BUILD": {"domain": "SOCIAL", "desc": "协作完成"},
}

static func has(capability: String) -> bool:
	return CAPABILITIES.has(capability)

static func domain_of(capability: String) -> String:
	var entry: Dictionary = CAPABILITIES.get(capability, {})
	return str(entry.get("domain", ""))

static func all_ids() -> Array:
	return CAPABILITIES.keys()

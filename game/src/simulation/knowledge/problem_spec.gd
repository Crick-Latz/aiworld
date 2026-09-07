class_name ProblemSpec
extends RefCounted
## P6.0 §8 Problem Ontology——Planner 用来寻找解决手段的语义描述。
## 不替换现有 Need/Goal（P1 冻结层不动）：Need 是生理槽，Goal 是决策层目标，
## Problem 是"知识检索的查询语义"——它声明什么资源/状态能使之满足。

const PROBLEMS := {
	"HUNGER": {"satisfied_by": ["FOOD"], "desc": "需要食物"},
	"THIRST": {"satisfied_by": ["WATER"], "desc": "需要水"},
	"EXPOSURE": {"satisfied_by": ["SHELTER"], "desc": "需要遮蔽"},
	"COLD": {"satisfied_by": ["HEAT_SOURCE", "INSULATION"], "desc": "需要保暖"},
	"DANGER": {"satisfied_by": ["SAFETY"], "desc": "处于危险"},
	"PREDATOR_THREAT": {"satisfied_by": ["SAFETY"], "requires": ["DEFEND", "FLEE"], "desc": "捕食者威胁"},
	"LACK_OF_STORAGE": {"satisfied_by": ["STORAGE"], "desc": "缺乏储存手段"},
	"LACK_OF_TOOL": {"satisfied_by": ["TOOL"], "desc": "缺乏工具"},
	"LACK_OF_SHELTER": {"satisfied_by": ["SHELTER"], "desc": "缺乏住所"},
	"ISOLATION": {"satisfied_by": ["COMPANY", "CONTACT"], "desc": "孤独隔绝"},
	"RESOURCE_SHORTAGE": {"satisfied_by": ["RESOURCE"], "desc": "资源短缺"},
	"ESCAPE_DESIRE": {"satisfied_by": ["ESCAPE_MEANS"], "desc": "想离开此地"},
	"SOCIAL_THREAT": {"satisfied_by": ["SAFETY"], "requires": ["DEFEND", "THREATEN"], "desc": "人际威胁"},
}

static func all_problems() -> Array:
	return PROBLEMS.keys()

static func satisfied_by(problem: String) -> Array:
	var entry: Dictionary = PROBLEMS.get(problem, {})
	return entry.get("satisfied_by", [])

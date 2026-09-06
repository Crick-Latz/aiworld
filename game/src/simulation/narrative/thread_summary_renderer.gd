class_name ThreadSummaryRenderer
extends RefCounted
## P4-2 Thread Summary 渲染器（确定性模板）：
## 把一条跨天 StoryThread 写成一段人类可读的故事摘要。
## 所有内容从 ThreadIR 的 source_event_ids 回溯——无源不写（省略而非补全）。
## 三种渲染深度：TIMELINE（逐节点）/ SUMMARY（一段话）/ TITLE（一行）。

const STATUS_LABELS := {"OPEN": "刚发生", "ACTIVE": "进行中", "DORMANT": "搁置", "RESOLVED": "已了结", "SUPERSEDED": "已合并"}
const RESOLUTION_LABELS := {"FULFILLED": "兑现了", "VIOLATED": "违背了", "BELIEF_REVISED": "想通了"}

## TIMELINE：逐节点时间线（Observer 点击展开用）
static func render_timeline(thread_ir: Dictionary, event_texts: Dictionary) -> Array:
	var lines: Array = []
	var status := str(thread_ir.get("status", ""))
	var label := str(STATUS_LABELS.get(status, status))
	var res := str(thread_ir.get("resolution", ""))
	if res != "":
		label += "·" + str(RESOLUTION_LABELS.get(res, res))
	lines.append("[%s] %s" % [label, str(thread_ir.get("title_seed", ""))])
	var days := str(thread_ir.get("opened_day", 1)) + "–" + str(thread_ir.get("last_activity_day", 1))
	lines.append("  第 %s 天" % days)
	var seqs: Array = thread_ir.get("source_event_ids", [])
	var shown := 0
	for seq in seqs:
		if shown >= 8:
			break
		var txt := str(event_texts.get(int(seq), ""))
		if txt == "":
			continue
		var day := int(event_texts.get("tick_%d" % int(seq), 0)) / 24 + 1
		lines.append("  第%d天  %s" % [day, txt.substr(0, 50)])
		shown += 1
	if shown == 0:
		lines.append("  （无详细事件）")
	return lines

## SUMMARY：一段话摘要（编年史/故事汇总用）
static func render_summary(thread_ir: Dictionary, event_texts: Dictionary) -> String:
	var title := str(thread_ir.get("title_seed", ""))
	var status := str(thread_ir.get("status", ""))
	var parts: Array = str(thread_ir.get("participants", "")).split(",")
	var who := str(parts[0]) if parts.size() > 0 else "某人"
	var other := str(parts[1]) if parts.size() > 1 else ""
	var opened := int(thread_ir.get("opened_day", 1))
	var closed := int(thread_ir.get("last_activity_day", opened))
	var duration := closed - opened + 1

	match str(thread_ir.get("thread_type", "")):
		"PROMISE_THREAD":
			if status == "RESOLVED" and str(thread_ir.get("resolution", "")) == "FULFILLED":
				return "%s对%s许下的承诺，经过 %d 天终于兑现了。" % [who, other, duration]
			elif status == "RESOLVED":
				return "%s对%s的承诺最终没能守住。" % [who, other]
			elif status == "DORMANT":
				return "%s欠%s的一份人情，已经 %d 天没人提起了。" % [who, other, duration]
			return "%s对%s的承诺还在进行中。" % [who, other]
		"EPISTEMIC_THREAD":
			if status == "RESOLVED":
				return "%s对%s的疑问，经过 %d 天终于有了答案。" % [who, other, duration]
			elif status == "DORMANT":
				return "%s心中的一个疑问渐渐沉寂了，但并未消散。" % who
			return "%s还在试图弄清楚关于%s的一件事。" % [who, other]
		"RELATIONSHIP_CONFLICT":
			if status == "RESOLVED":
				return "%s与%s的冲突终于平息了。" % [who, other]
			return "%s与%s之间的紧张关系仍在持续。" % [who, other]
		"RECIPROCITY_THREAD":
			return "%s与%s之间形成了互助的默契。" % [who, other]
		"INSTITUTION_CONFLICT":
			return "围绕营地规则，一场关于公平与遵守的较量已经持续了 %d 天。" % duration
		"AUTHORITY_THREAD":
			return "%s在群体中的影响力正在发生变化。" % who
		"RELOCATION_THREAD":
			return "%s选择了离开原来的住所。" % who
	return title

## TITLE：一行标题（Observer 列表用）
static func render_title(thread_ir: Dictionary) -> String:
	var status := str(thread_ir.get("status", ""))
	var icon := "●" if status == "ACTIVE" else ("○" if status == "DORMANT" else ("✓" if status == "RESOLVED" else "·"))
	return "%s %s" % [icon, str(thread_ir.get("title_seed", ""))]

## 从模拟构建 event_texts 映射（seq → text + tick）
static func build_event_lookup(sim) -> Dictionary:
	var out := {}
	for e in sim.events:
		var seq := int(e.get("seq", 0))
		out[seq] = str(e.get("text", ""))
		out["tick_%d" % seq] = int(e.get("tick", 0))
	return out

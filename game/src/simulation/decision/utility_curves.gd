class_name UtilityCurves
extends RefCounted
## 响应曲线库（阶段 B，M06 核心）。
## 参考 gamedev-skills/ai-behavior-trees-utility-ai/references/utility-ai-system.md。
## 每个函数：输入 0..1 的归一化事实，输出 0..1 的欲望强度。
## 性格特质通过修改曲线参数（斜率/阈值/指数）来影响行为，而非硬编码 if/else。

# 线性：欲望与事实成正比。slope>1 更敏感，slope<1 更迟钝。
static func linear(t: float, slope := 1.0, y_intercept := 0.0) -> float:
	t = clampf(t, 0.0, 1.0)
	return clampf(slope * t + y_intercept, 0.0, 1.0)

# 二次曲线：开始不敏感，接近 1 时急剧上升（"快饿死了才拼命找食物"）。
static func quadratic(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t

# 反二次：开始就很高，后面平缓（"刚开始饿就想吃东西"）。
static func inverse_quadratic(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return 1.0 - (1.0 - t) * (1.0 - t)

# 指数曲线：k 越大越陡峭（"只有极端情况才触发"）。
static func exponential(t: float, k := 4.0) -> float:
	t = clampf(t, 0.0, 1.0)
	return clampf((exp(k * t) - 1.0) / (exp(k) - 1.0), 0.0, 1.0)

# S 形曲线：mid 是转折点（"健康低于 40% 才想逃跑"→mid=0.4）。
static func sigmoid(t: float, k := 8.0, mid := 0.5) -> float:
	t = clampf(t, 0.0, 1.0)
	return clampf(1.0 / (1.0 + exp(-k * (t - mid))), 0.0, 1.0)

# 平滑阶梯：两端零斜率，中间平滑（默认的"软阈值"）。
static func smoothstep(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

# ── 工具函数 ──

# 归一化：把原始值映射到 0..1（支持反向范围 a>b）
static func inverse_lerp(value: float, a: float, b: float) -> float:
	if a == b:
		return 1.0 if value >= b else 0.0
	return clampf((value - a) / (b - a), 0.0, 1.0)

# 反转：高→低（例：健康越高，治疗欲望越低）
static func invert(t: float) -> float:
	return 1.0 - clampf(t, 0.0, 1.0)

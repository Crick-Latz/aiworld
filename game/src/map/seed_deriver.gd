class_name SeedDeriver
extends RefCounted
## 稳定种子派生（WP-03）。
## 算法固定：UTF-8 文本 "<world_seed>:<namespace>:<index>" 的 SHA-256，
## 前八字节按大端读取，首字节先与 0x7f => 恒为 0..INT64_MAX 的 63 位非负整数。

static func derive(world_seed: int, ns: String, index: int = 0) -> int:
	var text := "%d:%s:%d" % [world_seed, ns, index]
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(text.to_utf8_buffer())
	var digest: PackedByteArray = ctx.finish()
	var v := digest[0] & 0x7f
	for i in range(1, 8):
		v = (v << 8) | digest[i]
	return v

# FastNoiseLite 只吃 32 位 seed
static func derive32(world_seed: int, ns: String, index: int = 0) -> int:
	return derive(world_seed, ns, index) & 0x7fffffff

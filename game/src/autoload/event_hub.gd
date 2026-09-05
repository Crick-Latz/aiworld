extends Node
## EventHub：信号汇总（WP-02 / WP-04）。只声明当前需要的信号，不拥有任何状态。

signal config_loaded(ok: bool)
signal world_loaded(ok: bool, world_id: String)
signal world_load_failed(code: String, message: String)
signal debug_overlay_toggled(visible: bool)
signal player_tile_changed(actor_id: String, tile: Vector3i)
signal player_interacted(target_id: String, display_name: String)

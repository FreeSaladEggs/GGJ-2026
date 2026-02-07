extends Node3D

@export var powerup_scene: PackedScene
@export var spawn_area_size: Vector2 = Vector2(30, 30) # How wide the area is
@export var spawn_height: float = 20.0
@export var ground_height: float = 0.0

func _ready():
	# Only the server spawns items
	if multiplayer.is_server():
		var timer = Timer.new()
		timer.wait_time = 8.0 # Spawn every 8 seconds
		timer.autostart = true
		timer.timeout.connect(_spawn_item)
		add_child(timer)

func _spawn_item():
	var pos = Vector3(
	randf_range(-spawn_area_size.x/2, spawn_area_size.x/2),
	spawn_height, # This uses the variable above
	randf_range(-spawn_area_size.y/2, spawn_area_size.y/2)
)
	spawn_rpc.rpc(pos)

@rpc("any_peer", "call_local", "reliable")
func spawn_rpc(pos: Vector3):
	# Ignore spoofed client calls; allow server or server-sent RPCs only.
	var sender_id = multiplayer.get_remote_sender_id()
	if not multiplayer.is_server() and sender_id != 1:
		return
	var item = powerup_scene.instantiate()
	add_child(item)
	item.position = pos
	item.setup_fall(ground_height)

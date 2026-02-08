extends Node

# --- CONFIGURATION ---
# Drag your .tres files here
var day_environment = load("res://Enviroment/day.tres")
var night_environment = load("res://Enviroment/night.tres")

# Drag your Golden Mask scene here
@export var mask_scene: PackedScene = preload("res://scenes/level/golden_mask.tscn")

# How big is the area where the mask can spawn?
@export var spawn_range: float = 50.0 
@export var spawn_height: float = 1.0 # Height above ground

var _is_day: bool = true
var day_night_timer: Timer = null

@onready var world_environment: WorldEnvironment = null

func _ready():
	add_to_group("DayNightSystem")
	randomize() # Ensure random numbers are actually random
	
	var root_scene = get_tree().get_current_scene()
	if root_scene:
		world_environment = root_scene.find_child("WorldEnvironment", true, false)
		
	if not world_environment:
		push_error("WorldEnvironment node not found. Cannot switch day/night.")
	
	# Start with day environment
	_is_day = true
	switch_to_day()

	# SERVER SIDE TIMER LOGIC
	if multiplayer.is_server():
		day_night_timer = Timer.new()
		day_night_timer.wait_time = 30.0 # Time per phase
		day_night_timer.one_shot = false
		day_night_timer.autostart = true
		day_night_timer.timeout.connect(_toggle_day_night)
		add_child(day_night_timer)
		day_night_timer.start()
		
		# Sync initial state
		_set_day_state.rpc(_is_day)
	else:
		request_day_state.rpc_id(1)

func _toggle_day_night():
	if not multiplayer.is_server():
		return
		
	_is_day = not _is_day
	
	# --- LOGIC: NEW DAY HAS STARTED ---
	if _is_day:
		print("Sun is rising! Resetting Mask...")
		
		# 1. Force remove mask from any player holding it
		var players = get_tree().get_nodes_in_group("player")
		for p in players:
			# We call the function we added to Character.gd
			p.force_mask_reset.rpc()
			
		# 2. Spawn a new mask at a random spot
		_spawn_new_mask()

	# Sync the visual change to everyone
	_set_day_state.rpc(_is_day)

func _spawn_new_mask():
	if not mask_scene:
		print("Error: No mask_scene assigned in GameManager!")
		return

	var new_mask = mask_scene.instantiate()
	get_tree().get_current_scene().add_child(new_mask)
	
	# Calculate Random Position
	var random_x = randf_range(-spawn_range, spawn_range)
	var random_z = randf_range(-spawn_range, spawn_range)
	
	# Basic Position (Air Drop)
	# If your mask has physics (RigidBody), spawning high (e.g., 10.0) is fine.
	# If it is just an Area3D, we try to put it near the floor.
	
	# RAYCAST METHOD (Safest to find floor)
	var space_state = get_tree().get_current_scene().get_world_3d().direct_space_state
	var from = Vector3(random_x, 50.0, random_z)
	var to = Vector3(random_x, -50.0, random_z)
	var query = PhysicsRayQueryParameters3D.create(from, to)
	
	# We can mask the raycast to only hit the "Floor" layer if you know the bit (e.g., 1)
	# query.collision_mask = 1 
	
	var result = space_state.intersect_ray(query)
	
	if result:
		# Found the floor, place it slightly above
		new_mask.global_position = result.position + Vector3(0, spawn_height, 0)
	else:
		# Didn't find floor (maybe a hole?), use default height
		new_mask.global_position = Vector3(random_x, spawn_height, random_z)
		
	print("New Mask Spawned at: ", new_mask.global_position)

# --- VISUALS ---

func switch_to_night():
	if world_environment:
		world_environment.environment = night_environment

func switch_to_day():
	if world_environment:
		world_environment.environment = day_environment

@rpc("any_peer", "call_local", "reliable")
func _set_day_state(is_day: bool):
	_is_day = is_day
	if _is_day:
		switch_to_day()
	else:
		switch_to_night()

@rpc("any_peer", "call_local", "reliable")
func request_day_state():
	if not multiplayer.is_server():
		return
	var sender_id = multiplayer.get_remote_sender_id()
	_set_day_state.rpc_id(sender_id, _is_day)

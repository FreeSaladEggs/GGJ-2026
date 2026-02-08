extends CharacterBody3D
class_name Character

# --- STATS ---
var NORMAL_SPEED = 6.0
var SPRINT_SPEED = 10.0
var JUMP_VELOCITY = 10.0
var KNOCKBACK_FORCE = 25.0 

var _base_normal_speed = 6.0
var _base_sprint_speed = 10.0
var _base_jump = 10.0
var _base_knockback = 25.0

var powerup_timer: Timer
var STUN_DURATION = 0.4

# --- STATE VARS ---
var _is_dead = false # NEW: Tracks death state
var _is_stunned = false
var _is_frozen_by_green = false 
var _is_attacking = false
var _enemies_hit_this_attack = [] 
var _saved_nickname: String = "" 
var _has_golden_mask: bool = false
var _current_skin_color: SkinColor = SkinColor.BLUE 
var _was_on_floor: bool = true 
var canGetAbility: bool = true

# --- GREEN ABILITY VARS ---
var _green_ability_cooldown: float = 0.0
const GREEN_COOLDOWN_MAX = 5.0
const GREEN_FREEZE_DURATION = 2.0

# --- RED ABILITY VARS ---
var _red_ability_cooldown: float = 0.0
const RED_COOLDOWN_MAX = 20.0
var _lava_plane: MeshInstance3D = null
var _is_lava_active_globally: bool = false 

# --- YELLOW ABILITY VARS ---
var _yellow_ability_cooldown: float = 0.0
const YELLOW_COOLDOWN_MAX = 1.0
const LIGHTNING_COUNT = 10
const LIGHTNING_RADIUS = 60
const LIGHTNING_HIT_RADIUS = 5 

# --- GRAB MECHANIC VARS ---
var _grab_area: Area3D
var _grab_collision: CollisionShape3D
var _grab_mesh: MeshInstance3D
var _is_expanding_grab: bool = false
var _current_grab_radius: float = 0.0
const MAX_GRAB_RADIUS = 50.0
const GRAB_SPEED = 25.0

# --- GIANT & EARTHQUAKE VARS ---
var _stun_cube: MeshInstance3D
const GIANT_SCALE_FACTOR = 2.5
var _giant_tween: Tween
var _is_giant: bool = false 

enum SkinColor { BLUE, YELLOW, GREEN, RED }

# --- NODES ---
@onready var nickname: Label3D = $PlayerNick/Nickname
var player_inventory: PlayerInventory

@export_category("Objects")
@export var _body: Node3D = null
@export var _spring_arm_offset: Node3D = null
@onready var _camera: Camera3D = $SpringArmOffset/SpringArm3D/Camera3D
# We need the main collision shape to disable it on death
@onready var _main_collision: CollisionShape3D = $CollisionShape3D 

@export_category("Skin Colors")
@export var blue_texture : CompressedTexture2D
@export var yellow_texture : CompressedTexture2D
@export var green_texture : CompressedTexture2D
@export var red_texture : CompressedTexture2D

@onready var head_mask = get_node_or_null("3DGodotRobot/RobotArmature/Skeleton3D/BoneAttachment3D/Golden Mask")
@onready var _bottom_mesh: MeshInstance3D = get_node("3DGodotRobot/RobotArmature/Skeleton3D/Bottom")
@onready var _chest_mesh: MeshInstance3D = get_node("3DGodotRobot/RobotArmature/Skeleton3D/Chest")
@onready var _face_mesh: MeshInstance3D = get_node("3DGodotRobot/RobotArmature/Skeleton3D/Face")
@onready var _limbs_head_mesh: MeshInstance3D = get_node("3DGodotRobot/RobotArmature/Skeleton3D/Llimbs and head")

var _current_speed: float
var _respawn_point = Vector3(0, 5, 0)
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

var can_double_jump = true
var has_double_jumped = false

func _enter_tree():
	set_multiplayer_authority(str(name).to_int())
	$SpringArmOffset/SpringArm3D/Camera3D.current = is_multiplayer_authority()

func _ready():
	add_to_group("player")
	
	_setup_grab_nodes()
	_setup_stun_cube()
	
	if nickname:
		_saved_nickname = nickname.text

	var bone_attach = find_child("BoneAttachment3D", true, false)
	if bone_attach:
		var existing_mask = bone_attach.find_child("Golden Mask", true, false)
		if existing_mask:
			existing_mask.visible = false 
			_has_golden_mask = false
			if existing_mask is Area3D:
				existing_mask.monitoring = false
				existing_mask.monitorable = false

	if is_multiplayer_authority():
		player_inventory = PlayerInventory.new()
		_add_starting_items()
	elif multiplayer.is_server():
		player_inventory = PlayerInventory.new()
		_add_starting_items()
	else:
		if get_multiplayer_authority() == multiplayer.get_unique_id():
			request_inventory_sync.rpc_id(1)

# --- SETUP FUNCTIONS (GRAB/STUN) ---
func _setup_grab_nodes():
	_grab_area = Area3D.new()
	add_child(_grab_area)
	_grab_area.monitoring = false
	_grab_area.monitorable = false
	
	_grab_collision = CollisionShape3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = 1.0 
	_grab_collision.shape = sphere
	_grab_area.add_child(_grab_collision)
	
	_grab_mesh = MeshInstance3D.new()
	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = 1.0
	sphere_mesh.height = 2.0
	
	var material = StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.5, 0, 1, 0.3)
	material.emission_enabled = true
	material.emission = Color(0.5, 0, 1)
	material.emission_energy_multiplier = 2.0
	sphere_mesh.material = material
	
	_grab_mesh.mesh = sphere_mesh
	add_child(_grab_mesh)
	_grab_mesh.visible = false

func _setup_stun_cube():
	_stun_cube = MeshInstance3D.new()
	var cube_mesh = BoxMesh.new()
	cube_mesh.size = Vector3(1.2, 0.2, 1.2) 
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0, 1, 0, 1) # Bright Green
	mat.emission_enabled = true
	mat.emission = Color(0, 1, 0)
	mat.emission_energy_multiplier = 1.0
	cube_mesh.material = mat
	
	_stun_cube.mesh = cube_mesh
	add_child(_stun_cube)
	_stun_cube.position = Vector3(0, 0, 0)
	_stun_cube.visible = false

# --- DEATH LOGIC (UPDATED) ---

@rpc("any_peer", "call_local", "reliable")
func trigger_death():
	if _is_dead: return
	print(name, " has died!")
	
	_is_dead = true
	_body.play_hurt_animation()

# --- UPDATED LIGHTNING LOGIC (COLLISION BASED) ---

@rpc("any_peer", "call_local", "reliable")
func trigger_yellow_lightning(strike_positions: Array, source_id: int):
	# 1. VISUALS: Everyone (Clients + Server) does this
	for pos in strike_positions:
		_spawn_lightning_bolt_visual(pos)
	
	# 2. LOGIC: ONLY the Server spawns the kill zones
	# This ensures the "Hit" is calculated authoritatively
	if multiplayer.is_server():
		for pos in strike_positions:
			# TEMPORARY DEBUG VISUAL
			var debug_circle = MeshInstance3D.new()
			var cylinder = CylinderMesh.new()
			cylinder.top_radius = LIGHTNING_HIT_RADIUS
			cylinder.bottom_radius = LIGHTNING_HIT_RADIUS
			cylinder.height = 0.1
			debug_circle.mesh = cylinder
			get_tree().root.add_child(debug_circle)
			debug_circle.global_position = pos
			_spawn_server_hit_zone(pos, source_id)

func _spawn_server_hit_zone(pos: Vector3, attacker_id: int):
	# Create a temporary Area3D to detect players
	var hit_area = Area3D.new()
	var col = CollisionShape3D.new()
	var shape = CylinderShape3D.new()
	
	# Configure the shape (Cylinder is best for vertical bolts)
	shape.radius = LIGHTNING_HIT_RADIUS
	shape.height = 10.0 # Tall enough to hit jumping players
	col.shape = shape
	
	hit_area.add_child(col)
	get_tree().get_current_scene().add_child(hit_area)
	hit_area.global_position = pos
	
	# Connect the collision signal
	# We use a lambda function to handle the hit logic immediately
	hit_area.body_entered.connect(func(body):
		if body is Character and body.name != str(attacker_id): # Don't kill the caster
			_server_handle_lightning_hit(body)
	)
	
	# Cleanup: Destroy the detection zone after 0.5 seconds
	await get_tree().create_timer(0.5).timeout
	hit_area.queue_free()

func _server_handle_lightning_hit(victim: Character):
	# This function ONLY runs on the Server
	if victim._is_dead: return
	
	# CHECK: Does the victim have the mask?
	if victim._has_golden_mask:
		print("Server: ", victim.name, " survived lightning (Has Mask)")
		return

	# CHECK: Is it the Red Lava skin (optional immunity?)
	# If not, they die.
	print("Server: ", victim.name, " hit by lightning! KILLING NOW.")
	
	# Force the death on the victim
	victim.trigger_death.rpc()

func apply_lightning_hit():
	if _is_dead: return
	
	if _has_golden_mask:
		print("[DEBUG] Blocked by Mask!")
		return
	
	print("[DEBUG] No Mask! Triggering Death.")
	trigger_death.rpc() # This will broadcast death to everyone


func _spawn_lightning_bolt_visual(pos: Vector3):
	var mesh_inst = MeshInstance3D.new()
	var cylinder = CylinderMesh.new()
	cylinder.top_radius = 0.5
	cylinder.bottom_radius = 0.5
	cylinder.height = 50.0 
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 0) 
	mat.emission_enabled = true
	mat.emission = Color(1, 1, 0)
	mat.emission_energy_multiplier = 5.0 
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_inst.mesh = cylinder
	mesh_inst.material_override = mat
	get_tree().get_current_scene().add_child(mesh_inst)
	mesh_inst.global_position = pos
	mesh_inst.global_position.y += 25.0 
	var tween = create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.5).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_callback(mesh_inst.queue_free).set_delay(0.5)


# --- LAVA ABILITY (SERVER-SIDE COLLISION) ---

@rpc("any_peer", "call_local", "reliable")
func trigger_lava_floor(caster_id: int):
	# 1. VISUALS: Everyone creates the mesh so they can see the warning
	var lava_mesh = MeshInstance3D.new()
	var plane_mesh = PlaneMesh.new()
	plane_mesh.size = Vector2(100, 100) # Big area
	lava_mesh.mesh = plane_mesh
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 0, 0.6) # Start Yellow
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(1, 1, 0)
	lava_mesh.material_override = mat
	
	get_tree().get_current_scene().add_child(lava_mesh)
	lava_mesh.global_position = Vector3(0, 0.05, 0) # Slightly above floor to avoid Z-fighting
	
	# Start the color changing sequence
	_run_lava_sequence(lava_mesh, mat, caster_id)

func _run_lava_sequence(lava_mesh: MeshInstance3D, mat: StandardMaterial3D, caster_id: int):
	# PHASE 1: YELLOW (Warning)
	await get_tree().create_timer(2.0).timeout
	if not is_instance_valid(lava_mesh): return
	
	# PHASE 2: ORANGE (Danger Close)
	mat.albedo_color = Color(1, 0.5, 0, 0.7)
	mat.emission = Color(1, 0.5, 0)
	
	await get_tree().create_timer(3.0).timeout
	if not is_instance_valid(lava_mesh): return
	
	# PHASE 3: RED (DEADLY)
	mat.albedo_color = Color(1, 0, 0, 0.8)
	mat.emission = Color(1, 0, 0)
	mat.emission_energy_multiplier = 3.0
	
	# --- SERVER LOGIC STARTS HERE ---
	if multiplayer.is_server():
		# The floor is now deadly. Spawn the kill zone.
		_spawn_lava_kill_zone(lava_mesh.global_position, caster_id)
	
	# Cleanup Visuals after 10 seconds
	await get_tree().create_timer(10.0).timeout
	if is_instance_valid(lava_mesh):
		lava_mesh.queue_free()

func _spawn_lava_kill_zone(pos: Vector3, caster_id: int):
	# Create the invisible detection area
	var kill_area = Area3D.new()
	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	
	# Match the size of the visual plane (100x100)
	# Height is 2.0 to catch jumping/hovering players slightly above ground
	shape.size = Vector3(100, 2.0, 100) 
	col.shape = shape
	
	kill_area.add_child(col)
	get_tree().get_current_scene().add_child(kill_area)
	
	# Position it so the bottom is at y=0, top is at y=2
	kill_area.global_position = pos + Vector3(0, 1.0, 0) 
	
	# 1. CONNECT SIGNAL: Catch anyone walking INTO the lava
	kill_area.body_entered.connect(func(body):
		_check_lava_death(body)
	)
	
	# 2. IMMEDIATE CHECK: Catch anyone ALREADY standing there
	# We wait one physics frame to ensure the Area3D updates its overlaps
	await get_tree().physics_frame
	for body in kill_area.get_overlapping_bodies():
		_check_lava_death(body)
		
	# 3. CLEANUP: Remove the kill zone when the lava ends (10 seconds)
	await get_tree().create_timer(10.0).timeout
	if is_instance_valid(kill_area):
		kill_area.queue_free()

func _check_lava_death(body: Node):
	# This function runs ONLY on the Server
	if not body is Character: return
	if body._is_dead: return
	
	# IMMUNITY CHECK:
	# If they have the mask, they are safe.
	if body._has_golden_mask:
		print("Server: ", body.name, " is immune to lava (Mask equipped).")
		return
	
	# If no mask, they die.
	print("Server: ", body.name, " stepped in LAVA! Killing...")
	body.trigger_death.rpc()

@rpc("call_local", "reliable")
func trigger_green_blast(source_id: int):
	var all_players = get_tree().get_nodes_in_group("player")
	for player in all_players:
		var pid = player.get_multiplayer_authority()
		if pid != source_id:
			player.apply_green_freeze(GREEN_FREEZE_DURATION)

func apply_green_freeze(duration: float):
	if _is_dead: return
	print("[DEBUG] ", name, " Hit by GREEN BLAST!")
	_is_frozen_by_green = true
	if _stun_cube:
		_stun_cube.visible = true
	get_tree().create_timer(duration).timeout.connect(_remove_green_freeze)

func _remove_green_freeze():
	_is_frozen_by_green = false
	if _stun_cube:
		_stun_cube.visible = false

@rpc("call_local", "reliable")
func trigger_earthquake(source_id: int):
	var all_players = get_tree().get_nodes_in_group("player")
	for player in all_players:
		if player.is_multiplayer_authority():
			player.shake_camera(0.5, 0.5)
			var player_id = player.get_multiplayer_authority()
			if player_id != source_id:
				if player.is_on_floor():
					player.apply_earthquake_knockup()

func apply_earthquake_knockup():
	if _is_dead: return
	velocity.y = 20.0 
	_is_stunned = true 
	get_tree().create_timer(1.2).timeout.connect(func(): _is_stunned = false)

func shake_camera(duration: float, intensity: float):
	if not _camera: return
	var original_h = 0.0 
	var original_v = 0.0
	var shake_tween = create_tween()
	var steps = 15 
	var step_duration = duration / float(steps)
	for i in range(steps):
		var random_offset = Vector2(randf_range(-intensity, intensity), randf_range(-intensity, intensity))
		shake_tween.tween_property(_camera, "h_offset", random_offset.x, step_duration)
		shake_tween.parallel().tween_property(_camera, "v_offset", random_offset.y, step_duration)
	shake_tween.tween_property(_camera, "h_offset", original_h, step_duration)
	shake_tween.parallel().tween_property(_camera, "v_offset", original_v, step_duration)

# --- MASK VISUALS ---

func check_green_mask_logic(_is_equipping: bool): pass

func check_blue_mask_logic(is_equipping: bool):
	if not is_multiplayer_authority(): return
	if is_equipping and _current_skin_color == SkinColor.BLUE and not _is_currently_day() :
		set_giant_state.rpc(true)
	else:
		if _is_giant: set_giant_state.rpc(false)

@rpc("any_peer", "call_local", "reliable")
func set_giant_state(active: bool):
	_is_giant = active
	if _giant_tween: _giant_tween.kill()
	_giant_tween = create_tween()
	var target_scale = Vector3.ONE
	if active: target_scale = Vector3(GIANT_SCALE_FACTOR, GIANT_SCALE_FACTOR, GIANT_SCALE_FACTOR)
	_giant_tween.tween_property(self, "scale", target_scale, 1.0).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

@rpc("any_peer", "call_local", "reliable")
func equip_mask_visual():
	var bone_attach = find_child("BoneAttachment3D", true, false)
	if not bone_attach: return
	var mask = bone_attach.find_child("Golden Mask", true, false)
	if not mask:
		var mask_path = "res://scenes/level/golden_mask.tscn" 
		if ResourceLoader.exists(mask_path):
			var mask_scene = load(mask_path)
			mask = mask_scene.instantiate()
			bone_attach.add_child(mask)
			mask.name = "Golden Mask"
			mask.transform = Transform3D.IDENTITY
	if mask:
		mask.set("is_equipped", true) 
		if mask is Area3D:
			mask.set_deferred("monitoring", false)
			mask.set_deferred("monitorable", false)
		mask.visible = true
		_has_golden_mask = true
		canGetAbility = false
		check_green_mask_logic(true)
		check_blue_mask_logic(true)

@rpc("any_peer", "call_local", "reliable")
func remove_mask_visual():
	var mask = _get_mask_node()
	if mask:
		mask.set("is_equipped", false)
		if mask is Area3D:
			mask.set_deferred("monitoring", false)
			mask.set_deferred("monitorable", false)
		mask.visible = false
	_has_golden_mask = false
	check_green_mask_logic(false)
	check_blue_mask_logic(false)

func _get_mask_node() -> Node:
	var bone_attach = find_child("BoneAttachment3D", true, false)
	if not bone_attach: return null
	return bone_attach.find_child("Golden Mask", true, false)

@rpc("any_peer", "call_local", "reliable")
func request_mask_steal(target_peer_id: int):
	if not multiplayer.is_server(): return
	
	if _is_currently_day():
		var requester_id = multiplayer.get_remote_sender_id()
		if requester_id != get_multiplayer_authority(): return
		var target: Character = _get_player_by_authority(target_peer_id)
		if not target or target == self: return
		if _has_golden_mask: return
		if not target._has_golden_mask: return
		target.remove_mask_visual.rpc()
		equip_mask_visual.rpc()
		_server_transfer_mask_inventory(self, target)

func _get_player_by_authority(peer_id: int) -> Character:
	for node in get_tree().get_nodes_in_group("player"):
		if node is Character and node.get_multiplayer_authority() == peer_id:
			return node
	return null

func _server_transfer_mask_inventory(attacker: Character, target: Character) -> void:
	if not multiplayer.is_server(): return
	if target.player_inventory: target.player_inventory.remove_item("golden_mask", 1)
	if attacker.player_inventory:
		var item = ItemDatabase.get_item("golden_mask")
		if item: attacker.player_inventory.add_item(item, 1)
	_server_sync_inventory(attacker)
	_server_sync_inventory(target)

func _server_sync_inventory(player: Character) -> void:
	if not multiplayer.is_server(): return
	if not player.player_inventory: return
	var owner_id = player.get_multiplayer_authority()
	if owner_id != 1:
		player.sync_inventory_to_owner.rpc_id(owner_id, player.player_inventory.to_dict())
	else:
		var level_scene = get_tree().get_current_scene()
		if level_scene and level_scene.has_method("update_local_inventory_display"):
			level_scene.update_local_inventory_display()

# --- POWERUP SYSTEM ---

func apply_powerup(item_id: String):
	# --- NEW CHECK: ONLY ALLOW IN DAYLIGHT ---
	if not _is_currently_day() and _has_golden_mask:
		return # If it is Night, do nothing (Powerups disabled)
	# -----------------------------------------

	# Note: We removed the "if _has_golden_mask: return" check 
	# because you specified they can pick up items in daylight "even if he has the mask".

	_reset_stats_values()
	var new_text = ""
	var new_color = Color.WHITE
	
	match item_id:
		"speed":
			NORMAL_SPEED = 14.0
			SPRINT_SPEED = 22.0
			new_text = "FLASH SPEED!"
			new_color = Color.CYAN
		"jump":
			JUMP_VELOCITY = 22.0
			new_text = "MOON JUMP!"
			new_color = Color.GREEN
		"knockback":
			KNOCKBACK_FORCE = 80.0
			new_text = "TITAN PUNCH!"
			new_color = Color(1, 0.2, 0.2) 
		"slow_others":
			new_text = "BLACK HOLE!"
			new_color = Color.VIOLET
			trigger_grab_ability.rpc()
			
	update_powerup_label.rpc(new_text, new_color)
	
	if powerup_timer: powerup_timer.queue_free()
	powerup_timer = Timer.new()
	add_child(powerup_timer)
	powerup_timer.one_shot = true
	powerup_timer.timeout.connect(_on_powerup_timer_finished)
	powerup_timer.start(10.0)

func _on_powerup_timer_finished():
	_reset_stats_values()
	reset_powerup_label.rpc()

func _reset_stats_values():
	NORMAL_SPEED = _base_normal_speed
	SPRINT_SPEED = _base_sprint_speed
	JUMP_VELOCITY = _base_jump
	KNOCKBACK_FORCE = _base_knockback

@rpc("any_peer", "call_local", "reliable")
func update_powerup_label(text_override: String, color: Color):
	if nickname:
		if _saved_nickname == "" and nickname.text != text_override:
			_saved_nickname = nickname.text
		nickname.text = text_override
		nickname.modulate = color
		nickname.outline_modulate = Color.BLACK 

@rpc("any_peer", "call_local", "reliable")
func reset_powerup_label():
	if nickname:
		nickname.text = _saved_nickname
		nickname.modulate = Color.WHITE

# --- GRAB & PHYSICS ---

@rpc("any_peer", "call_local")
func trigger_grab_ability():
	_current_grab_radius = 1.0
	_is_expanding_grab = true
	_grab_mesh.scale = Vector3.ONE
	_grab_mesh.visible = true
	_grab_area.scale = Vector3.ONE
	if is_multiplayer_authority():
		_grab_area.monitoring = true

func _process_grab_mechanic(delta):
	if not _is_expanding_grab: return
	_current_grab_radius += delta * GRAB_SPEED
	var new_scale = Vector3(_current_grab_radius, _current_grab_radius, _current_grab_radius)
	_grab_mesh.scale = new_scale
	_grab_area.scale = new_scale
	if _current_grab_radius >= MAX_GRAB_RADIUS:
		_end_grab_ability()
		return
	if is_multiplayer_authority():
		var bodies = _grab_area.get_overlapping_bodies()
		for body in bodies:
			if body is Character and body != self and not body._is_dead:
				_perform_pull_on_target(body)
				_end_grab_ability() 
				break

func _perform_pull_on_target(target_body: Character):
	var pull_dir = (global_position - target_body.global_position).normalized()
	var pull_strength = 60.0 
	target_body.receive_pull.rpc_id(target_body.get_multiplayer_authority(), pull_dir, pull_strength)

func _end_grab_ability():
	_is_expanding_grab = false
	_grab_mesh.visible = false
	_grab_area.monitoring = false

@rpc("any_peer", "call_local", "reliable")
func receive_pull(direction: Vector3, strength: float):
	if _is_dead: return
	velocity = direction * strength
	velocity.y = 10.0 
	_is_stunned = true
	get_tree().create_timer(0.5).timeout.connect(func(): _is_stunned = false)

@rpc("any_peer", "call_local", "reliable")
func receive_knockback(direction: Vector3, force_override: float = -1):
	if _is_dead: return
	var final_force = force_override if force_override > 0 else 25.0
	velocity = direction * final_force
	velocity.y = 5.0
	_is_stunned = true
	get_tree().create_timer(STUN_DURATION).timeout.connect(func(): _is_stunned = false)

@rpc("any_peer", "call_local")
func apply_global_slow(caster_id: int): pass

func apply_rope_bounce(collision: KinematicCollision3D):
	var collider = collision.get_collider()
	var collision_normal = collision.get_normal()
	var bounce_dir = collision_normal.normalized()
	if collider.has_method("play_elastic_stretch"):
		collider.play_elastic_stretch(global_position)
	var final_dir = Vector3(bounce_dir.x, 0.2, bounce_dir.z)
	receive_knockback.rpc_id(get_multiplayer_authority(), final_dir, KNOCKBACK_FORCE * 1.8)

# --- PHYSICS PROCESS (UPDATED) ---
func _is_currently_day() -> bool:
	# Find the DayNightCycle script using the group we just added
	var day_night_node = get_tree().get_first_node_in_group("DayNightSystem")
	if day_night_node:
		return day_night_node._is_day
	return true # Default to Day if no system is found

func _physics_process(delta):
	# --- 1. DEATH CHECK ---
	if _is_dead: 
		velocity.x = 0
		velocity.z = 0
		velocity.y -= gravity * delta
		move_and_slide()
		return
		
	
	# --- 2. ALWAYS PROCESS GRAB VISUALS ---
	_process_grab_mechanic(delta)
	
	# --- 3. MULTIPLAYER AUTHORITY CHECK ---
	if not is_multiplayer_authority(): 
		return
	
	# --- 4. COOLDOWN MANAGEMENT ---
	if _green_ability_cooldown > 0.0: _green_ability_cooldown -= delta
	if _red_ability_cooldown > 0.0: _red_ability_cooldown -= delta
	if _yellow_ability_cooldown > 0.0: _yellow_ability_cooldown -= delta
	
	if _has_golden_mask:
		check_blue_mask_logic(true)
	# --- 5. CHECK TIME OF DAY ---
	# We store this in a variable to use for both Attacks and Ultimate
	var is_day = _is_currently_day() 
	
	# --- 6. INPUT: ATTACK (LMB) ---
	if Input.is_action_just_pressed("attack"):
		var ability_used = false
		
		# LOGIC: Check for Special Ability
		# STRICT RULE: Must have Mask AND it must NOT be Day (Night only)
		if _has_golden_mask and not is_day:
			
			# GREEN ABILITY
			if _current_skin_color == SkinColor.GREEN:
				if _green_ability_cooldown <= 0.0:
					_green_ability_cooldown = GREEN_COOLDOWN_MAX
					trigger_green_blast.rpc(get_multiplayer_authority())
					ability_used = true

			# RED ABILITY
			elif _current_skin_color == SkinColor.RED:
				if _red_ability_cooldown <= 0.0:
					_red_ability_cooldown = RED_COOLDOWN_MAX
					trigger_lava_floor.rpc(get_multiplayer_authority())
					ability_used = true
		
		# STANDARD ATTACK LOGIC:
		# This runs if:
		# 1. You don't have the mask OR
		# 2. It IS daytime (even if you have the mask) OR
		# 3. Your ability was on cooldown
		if not ability_used and not _is_attacking:
			start_lingering_attack()
			
	# --- 7. INPUT: YELLOW ULTIMATE (R Key) ---
	# LOGIC: Must have Mask AND it must NOT be Day
	if Input.is_key_pressed(KEY_R):
		if _has_golden_mask and not is_day:
			if _current_skin_color == SkinColor.YELLOW:
				if _yellow_ability_cooldown <= 0.0:
					_yellow_ability_cooldown = YELLOW_COOLDOWN_MAX
					
					# Calculate lightning positions
					var strikes = []
					for i in range(LIGHTNING_COUNT):
						var angle = randf() * TAU
						var dist = randf_range(2.0, LIGHTNING_RADIUS)
						var offset = Vector3(cos(angle) * dist, 0, sin(angle) * dist)
						strikes.append(global_position + offset)
					
					trigger_yellow_lightning.rpc(strikes, get_multiplayer_authority())
	
	# --- 8. HIT DETECTION (If punching) ---
	if _is_attacking:
		_perform_continuous_hit_check()
	
	# --- 9. GIANT EARTHQUAKE LOGIC ---
	var is_on_floor_now = is_on_floor()
	if is_on_floor_now and not _was_on_floor:
		if _is_giant:
			trigger_earthquake.rpc(get_multiplayer_authority())
	_was_on_floor = is_on_floor_now

	# --- 10. JUMP & GRAVITY ---
	if is_on_floor():
		if not _is_frozen_by_green:
			if not _is_stunned:
				can_double_jump = true
				has_double_jumped = false 
				if Input.is_action_just_pressed("jump"):
					velocity.y = JUMP_VELOCITY 
					can_double_jump = true
					_body.play_jump_animation("Jump")
		elif _is_frozen_by_green and Input.is_action_just_pressed("jump"):
			velocity.y = JUMP_VELOCITY 
			_body.play_jump_animation("Jump")
	else:
		velocity.y -= gravity * delta
		if can_double_jump and not has_double_jumped and Input.is_action_just_pressed("jump") and not _is_stunned:
			velocity.y = JUMP_VELOCITY
			has_double_jumped = true
			can_double_jump = false
			_body.play_jump_animation("Jump2")

	# --- 11. MOVEMENT & ANIMATION ---
	_move()
	move_and_slide()
	
	# Handle Rope Bouncing
	if is_multiplayer_authority():
		for i in get_slide_collision_count():
			var collision = get_slide_collision(i)
			var collider = collision.get_collider()
			if collider and collider.is_in_group("ropes"):
				apply_rope_bounce(collision)
				break 
	
	_body.animate(velocity)

func start_lingering_attack():
	_is_attacking = true
	_enemies_hit_this_attack.clear() 
	_body.play_attack_animation() 
	get_tree().create_timer(1.2).timeout.connect(stop_lingering_attack)

func stop_lingering_attack():
	_is_attacking = false
	_enemies_hit_this_attack.clear()

# --- HIT CHECK LOGIC ---

func _perform_continuous_hit_check():
	var hitbox = _body.get_node_or_null("HitBox")
	if not hitbox: return
	for body in hitbox.get_overlapping_bodies():
		if body is Character and body != self and not body in _enemies_hit_this_attack and not body._is_dead:
			
			# If I have the Mask -> They DIE.
			if _has_golden_mask and not _is_currently_day():
				body.trigger_death.rpc_id(body.get_multiplayer_authority())
			
			# If I don't have the Mask -> Knockback + Try Steal
			else:
				var knockback_dir = (body.global_position - global_position).normalized()
				knockback_dir.y = 0 
				body.receive_knockback.rpc_id(body.get_multiplayer_authority(), knockback_dir, KNOCKBACK_FORCE)
				request_mask_steal.rpc_id(1, body.get_multiplayer_authority())
			
			_enemies_hit_this_attack.append(body)


func freeze():
	velocity = Vector3.ZERO
	_current_speed = 0
	_body.animate(Vector3.ZERO)

func _move() -> void:
	if _is_stunned or _is_frozen_by_green:
		velocity.x = move_toward(velocity.x, 0, 0.5)
		velocity.z = move_toward(velocity.z, 0, 0.5)
		return

	var _input_direction: Vector2 = Vector2.ZERO
	if is_multiplayer_authority():
		_input_direction = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var _direction: Vector3 = transform.basis * Vector3(_input_direction.x, 0, _input_direction.y).normalized()
	is_running()
	if _spring_arm_offset:
		_direction = _direction.rotated(Vector3.UP, _spring_arm_offset.rotation.y)
	if _direction:
		velocity.x = _direction.x * _current_speed
		velocity.z = _direction.z * _current_speed
		_body.apply_rotation(velocity)
		return
	velocity.x = move_toward(velocity.x, 0, _current_speed)
	velocity.z = move_toward(velocity.z, 0, _current_speed)

func is_running() -> bool:
	if Input.is_action_pressed("shift"):
		_current_speed = SPRINT_SPEED
		return true
	else:
		_current_speed = NORMAL_SPEED
		return false



# --- RESPAWN (UPDATED) ---


@rpc("any_peer", "reliable")
func change_nick(new_nick: String):
	if nickname:
		nickname.text = new_nick
		_saved_nickname = new_nick 

func get_texture_from_name(skin_color: SkinColor) -> CompressedTexture2D:
	match skin_color:
		SkinColor.BLUE: return blue_texture
		SkinColor.GREEN: return green_texture
		SkinColor.RED: return red_texture
		SkinColor.YELLOW: return yellow_texture
		_: return blue_texture

@rpc("any_peer", "reliable")
func set_player_skin(skin_name: SkinColor) -> void:
	print("[DEBUG] Setting skin for ", name, " to ID: ", skin_name)
	_current_skin_color = skin_name
	var texture = get_texture_from_name(skin_name)
	set_mesh_texture(_bottom_mesh, texture)
	set_mesh_texture(_chest_mesh, texture)
	set_mesh_texture(_face_mesh, texture)
	set_mesh_texture(_limbs_head_mesh, texture)

func set_mesh_texture(mesh_instance: MeshInstance3D, texture: CompressedTexture2D) -> void:
	if mesh_instance:
		var material := mesh_instance.get_surface_override_material(0)
		if material and material is StandardMaterial3D:
			var new_material := material
			new_material.albedo_texture = texture
			mesh_instance.set_surface_override_material(0, new_material)

func _add_starting_items():
	if not player_inventory: return
	var sword = ItemDatabase.get_item("iron_sword")
	if sword: player_inventory.add_item(sword, 1)
	var potion = ItemDatabase.get_item("health_potion")
	if potion: player_inventory.add_item(potion, 3)

@rpc("any_peer", "call_local", "reliable")
func request_inventory_sync():
	if not multiplayer.is_server(): return
	var requesting_client = multiplayer.get_remote_sender_id()
	if player_inventory:
		sync_inventory_to_owner.rpc_id(requesting_client, player_inventory.to_dict())

@rpc("any_peer", "call_local", "reliable")
func sync_inventory_to_owner(inventory_data: Dictionary):
	if multiplayer.get_remote_sender_id() != 1: return
	if not is_multiplayer_authority(): return
	if not player_inventory: player_inventory = PlayerInventory.new()
	player_inventory.from_dict(inventory_data)
	var level_scene = get_tree().get_current_scene()
	if level_scene:
		if level_scene.has_method("update_local_inventory_display"):
			level_scene.update_local_inventory_display()
		if level_scene.has_node("InventoryUI"):
			level_scene.get_node("InventoryUI").refresh_display()

@rpc("any_peer", "call_local", "reliable")
func request_move_item(from_slot, to_slot, quantity = -1):
	if not multiplayer.is_server(): return
	if multiplayer.get_remote_sender_id() != get_multiplayer_authority(): return
	if not player_inventory: return
	var success = false
	if quantity == -1: success = player_inventory.move_item(from_slot, to_slot)
	if not success and quantity == -1: success = player_inventory.swap_items(from_slot, to_slot)
	elif quantity != -1: success = player_inventory.move_item(from_slot, to_slot, quantity)
	if success:
		var owner_id = get_multiplayer_authority()
		if owner_id != 1: sync_inventory_to_owner.rpc_id(owner_id, player_inventory.to_dict())

@rpc("any_peer", "call_local", "reliable")
func request_add_item(item_id: String, quantity: int = 1):
	if not multiplayer.is_server(): return
	var requesting_client = multiplayer.get_remote_sender_id()
	if requesting_client != get_multiplayer_authority() and requesting_client != 1: return
	if not player_inventory: return
	var item = ItemDatabase.get_item(item_id)
	if not item: return
	player_inventory.add_item(item, quantity)
	var owner_id = get_multiplayer_authority()
	if owner_id != 1: sync_inventory_to_owner.rpc_id(owner_id, player_inventory.to_dict())
	else:
		var level_scene = get_tree().get_current_scene()
		if level_scene and level_scene.has_method("update_local_inventory_display"):
			level_scene.update_local_inventory_display()

@rpc("any_peer", "call_local", "reliable")
func request_remove_item(item_id: String, quantity: int = 1):
	if not multiplayer.is_server(): return
	if multiplayer.get_remote_sender_id() != get_multiplayer_authority(): return
	if not player_inventory: return
	player_inventory.remove_item(item_id, quantity)
	var owner_id = get_multiplayer_authority()
	if owner_id != 1: sync_inventory_to_owner.rpc_id(owner_id, player_inventory.to_dict())
	
# --- ADD THIS TO THE BOTTOM OF Character.gd ---

@rpc("any_peer", "call_local", "reliable")
func force_mask_reset():
	# 1. Remove Visuals
	remove_mask_visual()
	
	# 2. Clear Inventory (Server Side Only)
	if multiplayer.is_server():
		if player_inventory and player_inventory.has_item("golden_mask"):
			player_inventory.remove_item("golden_mask", 1)
			# Sync the empty inventory back to the client
			_server_sync_inventory(self)
			print("Server: Mask stripped from ", name)

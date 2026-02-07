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
var _is_stunned = false
var _is_attacking = false
var _enemies_hit_this_attack = [] 
var _saved_nickname: String = "" 

enum SkinColor { BLUE, YELLOW, GREEN, RED }

# --- NODES ---
@onready var nickname: Label3D = $PlayerNick/Nickname
var player_inventory: PlayerInventory

@export_category("Objects")
@export var _body: Node3D = null
@export var _spring_arm_offset: Node3D = null

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
	
	if nickname:
		_saved_nickname = nickname.text

	# --- FIX START: HIDE MASK ON SPAWN ---
	# We look for the mask bone attachment. If it exists in the scene, hide it.
	var bone_attach = find_child("BoneAttachment3D", true, false)
	if bone_attach:
		var existing_mask = bone_attach.find_child("Golden Mask", true, false)
		if existing_mask:
			existing_mask.visible = false # Hide it so they don't spawn with it!
			
			# Also ensure physics are off for the head mask
			if existing_mask is Area3D:
				existing_mask.monitoring = false
				existing_mask.monitorable = false
	# --- FIX END ---

	if is_multiplayer_authority():
		player_inventory = PlayerInventory.new()
		_add_starting_items()
	elif multiplayer.is_server():
		player_inventory = PlayerInventory.new()
		_add_starting_items()
	else:
		if get_multiplayer_authority() == multiplayer.get_unique_id():
			request_inventory_sync.rpc_id(1)

# --- MASK VISUAL LOGIC ---

@rpc("any_peer", "call_local", "reliable")
func equip_mask_visual():
	var bone_attach = find_child("BoneAttachment3D", true, false)
	if not bone_attach: return

	var mask = bone_attach.find_child("Golden Mask", true, false)
	
	# If mask doesn't exist in the scene tree, load it
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
		
		# Turn off physics so the head-mask doesn't trigger collisions
		if mask is Area3D:
			mask.monitoring = false
			mask.monitorable = false
			
		mask.visible = true
		print("Mask equipped visually on: ", name)

# --- POWERUP SYSTEM ---

func apply_powerup(item_id: String):
	print("PowerUp Collected Locally: ", item_id)
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
			new_text = "TIME FREEZE!"
			new_color = Color.VIOLET
			apply_global_slow.rpc(multiplayer.get_unique_id())

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

# --- COMBAT & ABILITIES ---

@rpc("any_peer", "call_local", "reliable")
func receive_knockback(direction: Vector3, force_override: float = -1):
	var final_force = force_override if force_override > 0 else 25.0
	velocity = direction * final_force
	velocity.y = 5.0
	_is_stunned = true
	get_tree().create_timer(STUN_DURATION).timeout.connect(func(): _is_stunned = false)

@rpc("any_peer", "call_local")
func apply_global_slow(caster_id: int):
	if multiplayer.get_unique_id() == caster_id: return
	print("I have been slowed!")
	NORMAL_SPEED = 2.0
	SPRINT_SPEED = 3.0
	JUMP_VELOCITY = 5.0
	
	await get_tree().create_timer(5.0).timeout
	
	if not powerup_timer or powerup_timer.is_stopped():
		NORMAL_SPEED = _base_normal_speed
		SPRINT_SPEED = _base_sprint_speed
		JUMP_VELOCITY = _base_jump

# --- PHYSICS & MOVEMENT ---

func _physics_process(delta):
	if not is_multiplayer_authority(): return
	
	if Input.is_action_just_pressed("attack") and not _is_attacking:
		start_lingering_attack()
	
	if _is_attacking:
		_perform_continuous_hit_check()
	
	if is_on_floor():
		can_double_jump = true
		has_double_jumped = false 
		if Input.is_action_just_pressed("jump"):
			velocity.y = JUMP_VELOCITY 
			can_double_jump = true
			_body.play_jump_animation("Jump")
	else:
		velocity.y -= gravity * delta
		if can_double_jump and not has_double_jumped and Input.is_action_just_pressed("jump"):
			velocity.y = JUMP_VELOCITY
			has_double_jumped = true
			can_double_jump = false
			_body.play_jump_animation("Jump2")

	velocity.y -= gravity * delta

	_move()
	move_and_slide()
	_body.animate(velocity)

func start_lingering_attack():
	_is_attacking = true
	_enemies_hit_this_attack.clear() 
	_body.play_attack_animation() 
	get_tree().create_timer(1.2).timeout.connect(stop_lingering_attack)

func stop_lingering_attack():
	_is_attacking = false
	_enemies_hit_this_attack.clear()

func _perform_continuous_hit_check():
	var hitbox = _body.get_node_or_null("HitBox")
	if not hitbox: return
	for body in hitbox.get_overlapping_bodies():
		if body is Character and body != self and not body in _enemies_hit_this_attack:
			var knockback_dir = (body.global_position - global_position).normalized()
			knockback_dir.y = 0 
			body.receive_knockback.rpc_id(
				body.get_multiplayer_authority(), 
				knockback_dir, 
				KNOCKBACK_FORCE
			)
			_enemies_hit_this_attack.append(body)

func _process(_delta):
	if not is_multiplayer_authority(): return
	_check_fall_and_respawn()

func freeze():
	velocity = Vector3.ZERO
	_current_speed = 0
	_body.animate(Vector3.ZERO)

func _move() -> void:
	if _is_stunned:
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

func _check_fall_and_respawn():
	if global_transform.origin.y < -15.0:
		_respawn()

func _respawn():
	global_transform.origin = _respawn_point
	velocity = Vector3.ZERO

# --- COSMETICS & INV ---

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

# --- INVENTORY RPCS ---

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

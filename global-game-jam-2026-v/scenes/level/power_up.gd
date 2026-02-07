extends Area3D

# --- CONFIGURATION ---
var fall_speed: float = 8.0
var target_y: float = 0.0
var is_grounded: bool = false
var current_item_id: String = ""

@onready var label: Label3D = $Label3D
@onready var item_mesh: MeshInstance3D = $ItemMesh

# --- ITEM DATABASE ---
# This dictionary links the ID to the Name, Color, and Mesh
var ITEM_DB = {
	"speed": {
		"name": "Flash Speed",
		"color": Color(0, 1, 1), # Cyan
		"mesh_path": "res://assets/potions/blue_bottle.obj" 
	},
	"jump": {
		"name": "Moon Jump",
		"color": Color(0, 1, 0), # Green
		"mesh_path": "res://assets/boots/spring_boots.obj"
	},
	"knockback": {
		"name": "Titan Hit",
		"color": Color(1, 0, 0), # Red
		"mesh_path": "res://assets/weapons/hammer.obj"
	},
	"slow_others": {
		"name": "Time Freeze",
		"color": Color(0.5, 0, 0.5), # Purple
		"mesh_path": "res://assets/magic/hourglass.obj"
	}
}

func _ready():
	# 1. Pick a random powerup
	current_item_id = ITEM_DB.keys().pick_random()
	var data = ITEM_DB[current_item_id]
	
	# 2. Setup Visuals
	if label: label.text = data["name"]
	_load_visuals(data)
	
	# 3. Connect Collision
	body_entered.connect(_on_body_entered)

func _load_visuals(data):
	# Try to load the mesh, otherwise use a colored sphere
	if ResourceLoader.exists(data["mesh_path"]):
		item_mesh.mesh = load(data["mesh_path"])
	else:
		var sphere = SphereMesh.new()
		sphere.radius = 0.3
		sphere.height = 0.6
		item_mesh.mesh = sphere
		
	var mat = StandardMaterial3D.new()
	mat.albedo_color = data["color"]
	item_mesh.material_override = mat

func setup_fall(ground_height: float):
	target_y = ground_height

func _process(delta):
	if not is_grounded:
		position.y -= fall_speed * delta
		if position.y <= target_y:
			position.y = target_y
			is_grounded = true
	else:
		# Floating animation
		item_mesh.position.y = sin(Time.get_ticks_msec() / 500.0) * 0.2
		item_mesh.rotation.y += delta # Spin

func _on_body_entered(body):
	if body is Character:
		# Only the player who touched it should process this
		if body.is_multiplayer_authority():
			body.apply_powerup(current_item_id)
			# Tell server to destroy this object
			queue_free_rpc.rpc()

@rpc("any_peer", "call_local")
func queue_free_rpc():
	queue_free()

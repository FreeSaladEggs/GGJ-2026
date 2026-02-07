extends Area3D

# This stops the code from running when the mask is attached to a player
var is_equipped: bool = false 

func _ready():
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)

func _on_body_entered(body):
	# If this is the mask sitting on a player's face, ignore collisions
	if is_equipped:
		return 
	
	# Only the server decides who picks it up
	if not multiplayer.is_server():
		return

	if body is Character:
		print("Server: Player ", body.name, " picked up the mask.")
		
		# 1. Visually equip it on the player (RPC to everyone)
		body.equip_mask_visual.rpc()
		
		# 2. Add to inventory (Server logic)
		body.request_add_item("golden_mask", 1)
		
		# 3. DESTROY THE GROUND MASK FOR EVERYONE
		# We call an RPC so clients know to delete this specific object
		destroy_object.rpc()

@rpc("any_peer", "call_local", "reliable")
func destroy_object():
	queue_free()

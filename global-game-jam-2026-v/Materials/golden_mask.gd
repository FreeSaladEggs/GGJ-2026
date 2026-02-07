extends Area3D

func _ready():
	# Connect the signal automatically
	body_entered.connect(_on_body_entered)

func _on_body_entered(body):
	# 1. Check if the thing hitting the mask is a 'Character' (from your script)
	if body is Character:
		print("Collision detected with player!")
		
		# 2. Tell the player to show their head mask on all clients
		body.equip_mask_visual.rpc()
		
		# 3. Add it to the inventory (using your existing function)
		if multiplayer.is_server():
			body.request_add_item("golden_mask", 1)
		
		# 4. Delete the floor mask so it's "picked up"
		queue_free()

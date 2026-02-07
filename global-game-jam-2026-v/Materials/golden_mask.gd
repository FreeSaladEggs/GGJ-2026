extends Area3D

func _ready():
<<<<<<< Updated upstream
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
=======
	# Connect the signal so the function below runs on hit
	body_entered.connect(_on_body_entered)

func _on_body_entered(body):
	# Check if the body that hit the mask is a 'Character' (from your class_name)
	if body is Character and body.is_in_group("player"):
		print("Mask collected by player: ", body.name)
		
		# Access the inventory logic already in your player script
		if body.has_method("request_add_item"):
			# Change "golden_mask" to whatever the ID is in your ItemDatabase
			body.request_add_item.rpc_id(1, "golden_mask", 1) 
		
		queue_free() # Delete the mask from the world
>>>>>>> Stashed changes

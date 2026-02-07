extends Area3D

func _ready():
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

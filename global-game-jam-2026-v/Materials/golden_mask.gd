extends Area3D

# This MUST be at the very top, outside of any functions
var is_equipped: bool = false 

func _ready():
	# Connect the signal if you haven't in the editor
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)

func _on_body_entered(body):
	# If this is the one on the head, do nothing!
	if is_equipped:
		return 
		
	if body is Character:
		print("Ground mask picked up!")
		body.equip_mask_visual.rpc()
		
		if multiplayer.is_server():
			body.request_add_item("golden_mask", 1)
			
		queue_free() # Only the ground one dies

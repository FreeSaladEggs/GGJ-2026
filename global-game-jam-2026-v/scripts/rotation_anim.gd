extends Node3D

# This allows you to adjust the speed in the Inspector window
# Positive numbers rotate one way, negative numbers rotate the other
@export var rotation_speed_degrees : float = 90.0

func _process(delta: float) -> void:
	# We convert degrees to radians because rotate_y expects radians
	var rotation_radians = deg_to_rad(rotation_speed_degrees)
	
	# Apply the rotation based on time (delta)
	rotate_y(rotation_radians * delta)

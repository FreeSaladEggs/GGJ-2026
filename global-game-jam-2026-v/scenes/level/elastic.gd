extends StaticBody3D

@onready var mesh = $MeshInstance3D 

# This function handles the visual "bowstring" bend
func play_elastic_stretch(impact_position: Vector3):
	# 1. Calculate the direction from the rope to the player
	# This ensures the rope bends AWAY from the ring center
	var impact_local = to_local(impact_position)
	var bend_direction = impact_local.normalized() * 0.5 # 0.5 is how deep it dents
	
	var tween = create_tween()
	
	# PHASE 1: The Bend (Rope stretches out)
	# We move the mesh and slightly scale it to look stretched
	tween.tween_property(mesh, "position", bend_direction, 0.1).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(mesh, "scale", Vector3(1.1, 0.9, 1.1), 0.1)
	
	# PHASE 2: The Snap (Rope thwacks back)
	# TRANS_ELASTIC gives it that "boing" vibrating look
	tween.tween_property(mesh, "position", Vector3.ZERO, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(mesh, "scale", Vector3(1.0, 1.0, 1.0), 0.5)

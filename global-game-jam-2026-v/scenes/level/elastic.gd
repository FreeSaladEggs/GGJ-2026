extends StaticBody3D

@onready var mesh = $MeshInstance3D 

func play_elastic_stretch(impact_global_pos: Vector3):
	# 1. Figure out which way to bend
	# We move the mesh toward the player's impact point
	var local_impact = to_local(impact_global_pos)
	
	# We only want to bend on the horizontal plane (X and Z)
	var bend_vector = Vector3(local_impact.x, 0, local_impact.z).normalized() * 0.6
	
	var tween = create_tween()
	
	# PHASE 1: The "Denting" (Rope moves with the player)
	tween.tween_property(mesh, "position", bend_vector, 0.1).set_ease(Tween.EASE_OUT)
	
	# PHASE 2: The "Snap" (This is the arrow-style thwack)
	# TRANS_ELASTIC is what makes it vibrate/snap back instead of just growing
	tween.tween_property(mesh, "position", Vector3.ZERO, 0.6).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

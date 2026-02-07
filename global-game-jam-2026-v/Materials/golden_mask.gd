extends Area3D



func _on_body_entered(body):
	
	for i in self.get_overlapping_bodies() :
		print_debug("aaaaaaaaa")

extends Node


# Drag and drop your .tres files into these slots in the Inspector
var day_environment = load("res://Enviroment/day.tres")
var night_environment = load("res://Enviroment/night.tres")
var _is_day: bool = true

@onready var world_environment: WorldEnvironment = null

func switch_to_night():
	if not world_environment:
		return
	world_environment.environment = night_environment

func switch_to_day():
	if not world_environment:
		return
	world_environment.environment = day_environment


func _ready():
	var root_scene = get_tree().get_current_scene()
	if root_scene:
		world_environment = root_scene.find_child("WorldEnvironment", true, false)
	if not world_environment:
		push_error("WorldEnvironment node not found. Cannot switch day/night.")
	# Start with day environment
	switch_to_day()
	_is_day = true

	if multiplayer.is_server():
		var timer = Timer.new()
		timer.wait_time = 10.0
		timer.one_shot = false
		timer.autostart = true
		timer.timeout.connect(_toggle_day_night)
		add_child(timer)
		_set_day_state.rpc(_is_day)
	else:
		request_day_state.rpc_id(1)

func _toggle_day_night():
	if not multiplayer.is_server():
		return
	_is_day = not _is_day
	_set_day_state.rpc(_is_day)

@rpc("any_peer", "call_local", "reliable")
func _set_day_state(is_day: bool):
	_is_day = is_day
	if _is_day:
		switch_to_day()
	else:
		switch_to_night()

@rpc("any_peer", "call_local", "reliable")
func request_day_state():
	if not multiplayer.is_server():
		return
	var sender_id = multiplayer.get_remote_sender_id()
	_set_day_state.rpc_id(sender_id, _is_day)

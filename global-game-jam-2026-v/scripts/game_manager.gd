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

	var timer = Timer.new()
	timer.wait_time = 10.0
	timer.one_shot = false
	timer.autostart = true
	timer.timeout.connect(_toggle_day_night)
	add_child(timer)

func _toggle_day_night():
	_is_day = not _is_day
	if _is_day:
		switch_to_day()
	else:
		switch_to_night()

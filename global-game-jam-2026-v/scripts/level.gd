extends Node3D

@onready var players_container: Node3D = $PlayersContainer
@onready var main_menu: MainMenuUI = $MainMenuUI
@export var player_scene: PackedScene

@onready var multiplayer_chat: MultiplayerChatUI = $MultiplayerChatUI
@onready var inventory_ui: InventoryUI = $InventoryUI

var is_spawned = true
var chat_visible = false
var inventory_visible = false


func _ready():
	# --- STARTUP ---
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if DisplayServer.get_name() == "headless":
		print("Dedicated server starting...")
		Network.start_host("", "")

	multiplayer_chat.hide()
	main_menu.show_menu()
	multiplayer_chat.set_process_input(true)

	# Connect Menu Signals
	main_menu.host_pressed.connect(_on_host_pressed)
	main_menu.join_pressed.connect(_on_join_pressed)
	main_menu.quit_pressed.connect(_on_quit_pressed)

	if inventory_ui:
		inventory_ui.inventory_closed.connect(_on_inventory_closed)

	if multiplayer_chat:
		multiplayer_chat.message_sent.connect(_on_chat_message_sent)

	if not multiplayer.is_server():
		return

	Network.connect("player_connected", Callable(self, "_on_player_connected"))
	multiplayer.peer_disconnected.connect(_remove_player)

# ---------- MOUSE CONTROL LOGIC ----------
func _update_mouse_mode():
	# If any UI is open, the mouse must be visible
	if main_menu.is_menu_visible() or chat_visible or inventory_visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		# No UI is open: Capture mouse and clear focus from buttons/inputs
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().gui_release_focus()

# ---------- NETWORK HANDLERS ----------
func _on_player_connected(peer_id, player_info):
	_add_player(peer_id, player_info)

func _on_host_pressed(nickname: String, skin: String):
	main_menu.hide_menu()
	Network.start_host(nickname, skin)
	_update_mouse_mode() # Hide cursor when entering game

func _on_join_pressed(nickname: String, skin: String, address: String):
	main_menu.hide_menu()
	Network.join_game(nickname, skin, address)
	_update_mouse_mode() # Hide cursor when entering game

func _add_player(id: int, player_info : Dictionary):
	if DisplayServer.get_name() == "headless" and id == 1:
		return

	if players_container.has_node(str(id)):
		return

	var player = player_scene.instantiate()
	player.name = str(id)
	player.position = get_spawn_point()
	players_container.add_child(player, true)

	var nick = Network.players[id]["nick"]
	player.nickname.text = nick

	var skin_enum = player_info["skin"]
	player.set_player_skin(skin_enum)

func get_spawn_point() -> Vector3:
	var spawn_point = Vector2.from_angle(randf() * 2 * PI) * 10
	return Vector3(spawn_point.x, 0, spawn_point.y)

func _remove_player(id):
	if not multiplayer.is_server() or not players_container.has_node(str(id)):
		return
	var player_node = players_container.get_node(str(id))
	if player_node:
		player_node.queue_free()

func _on_quit_pressed() -> void:
	get_tree().quit()

# ---------- INPUT HANDLING ----------
func _input(event):
	# Chat Toggle
	if event.is_action_pressed("toggle_chat"):
		toggle_chat()
	
	# Handle Enter key for Chat
	elif chat_visible and multiplayer_chat.message.has_focus():
		if event is InputEventKey and event.keycode == KEY_ENTER and event.pressed:
			multiplayer_chat._on_send_pressed()
			get_viewport().set_input_as_handled()
	
	# Inventory Toggle
	elif event.is_action_pressed("inventory"):
		toggle_inventory()
	
	# Debug Keys
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_F1: _debug_add_item()
		if event.keycode == KEY_F2: _debug_print_inventory()

	# Manual Mouse Toggles (Only if main menu is closed)
	if not main_menu.is_menu_visible():
		if event.is_action_pressed("ui_cancel"): # Usually ESC
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		
		if event is InputEventMouseButton and event.pressed:
			_update_mouse_mode()

# ---------- MULTIPLAYER CHAT ----------
func toggle_chat():
	if main_menu.is_menu_visible(): return

	multiplayer_chat.toggle_chat()
	chat_visible = multiplayer_chat.is_chat_visible()
	_update_mouse_mode()

func is_chat_visible() -> bool:
	return multiplayer_chat.is_chat_visible()

func _on_chat_message_sent(message_text: String) -> void:
	var trimmed_message = message_text.strip_edges()
	if trimmed_message == "": return

	var nick = Network.players[multiplayer.get_unique_id()]["nick"]
	rpc("msg_rpc", nick, trimmed_message)

@rpc("any_peer", "call_local")
func msg_rpc(nick, msg):
	multiplayer_chat.add_message(nick, msg)

# ---------- INVENTORY SYSTEM ----------
func toggle_inventory():
	if main_menu.is_menu_visible(): return

	var local_player = _get_local_player()
	if not local_player: return

	inventory_visible = !inventory_visible
	if inventory_visible:
		inventory_ui.open_inventory(local_player)
	else:
		inventory_ui.close_inventory()
	
	_update_mouse_mode()

func _on_inventory_closed():
	inventory_visible = false
	_update_mouse_mode()

func is_inventory_visible() -> bool:
	return inventory_visible

func update_local_inventory_display():
	if inventory_ui:
		inventory_ui.refresh_display()

func _get_local_player() -> Character:
	var local_player_id = multiplayer.get_unique_id()
	if players_container.has_node(str(local_player_id)):
		return players_container.get_node(str(local_player_id)) as Character
	return null

# ---------- DEBUG & NOTIFICATIONS ----------
func _notification(what):
	if what == NOTIFICATION_READY:
		print("Controls: B (Inv), Enter/T (Chat), F1/F2 (Debug)")

func _debug_add_item():
	var local_player = _get_local_player()
	if local_player:
		var test_items = ["iron_sword", "health_potion", "leather_armor"]
		var random_item = test_items[randi() % test_items.size()]
		local_player.request_add_item.rpc_id(1, random_item, 1)

func _debug_print_inventory():
	var local_player = _get_local_player()
	if local_player and local_player.get_inventory():
		var inventory = local_player.get_inventory()
		for i in range(inventory.slots.size()):
			var slot = inventory.get_slot(i)
			if slot and not slot.is_empty():
				print("Slot ", i, ": ", slot.item_id, " x", slot.quantity)

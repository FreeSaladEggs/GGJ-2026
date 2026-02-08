extends Control
class_name MainMenuUI

signal host_pressed(nickname: String, skin: String)
signal join_pressed(nickname: String, skin: String, address: String)
signal quit_pressed

@onready var nick_input: LineEdit = $MainContainer/MainMenu/Option1/NickInput
@onready var address_input: LineEdit = $MainContainer/MainMenu/Option3/AddressInput
@onready var option_button: OptionButton = $MainContainer/MainMenu/Option2/OptionButton
func _ready():
	pass

func _on_host_pressed():
	var nickname = nick_input.text.strip_edges()
	var selected_idx = option_button.get_selected_id()
	var skin = option_button.get_item_text(selected_idx).to_lower()
	host_pressed.emit(nickname, skin)

func _on_join_pressed():
	var nickname = nick_input.text.strip_edges()
	var selected_idx = option_button.get_selected_id()
	var skin = option_button.get_item_text(selected_idx).to_lower()
	var address = address_input.text.strip_edges()
	join_pressed.emit(nickname, skin, address)

func _on_quit_pressed():
	quit_pressed.emit()

func show_menu():
	show()

func hide_menu():
	hide()

func is_menu_visible() -> bool:
	return visible

func get_nickname() -> String:
	return nick_input.text.strip_edges()

func get_skin() -> String:
	# Get the index of the currently selected item
	var selected_idx = option_button.get_selected_id()
	
	# Return the text of that item, formatted as lowercase
	return option_button.get_item_text(selected_idx).to_lower()

func get_address() -> String:
	return address_input.text.strip_edges()

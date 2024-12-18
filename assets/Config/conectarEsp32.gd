extends Node2D

@onready var ip_input: LineEdit = $ip_connect
@onready var connect_button: Button = $Button

func _ready() -> void:
	ip_input.text = "192.168.1.205:8080"
	
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	# Connect event only if it's not already connected
	connect_button.pressed.connect(_on_connect_pressed)

func _on_connect_pressed() -> void:
	ConnectionManager.last_url = ip_input.text
	print("Button pressed! IP:", ip_input.text)
	get_tree().change_scene_to_file("res://Level/Nivel Prueba.tscn")

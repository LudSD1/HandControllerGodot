extends Camera3D

var sensitivity: float = 0.3
var rotation_x: float = 0
var rotation_y: float = 0
@export var hand: Node3D
var move_speed: float = 5.0  # Velocidad de movimiento con las flechas

func _ready():
	look_at(Vector3.ZERO)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	# Hacer que la mano sea hija de la cámara
	if hand:
		# Ajusta estos valores para posicionar la mano en la pantalla
		hand.position = Vector3(0.5, -0.3, -0.5)
		# La mano se moverá con la cámara automáticamente al ser su hija
		add_child(hand)

func _unhandled_input(event):
	if event is InputEventMouseMotion:
		rotation_y -= event.relative.x * sensitivity
		rotation_x -= event.relative.y * sensitivity
		rotation_x = clamp(rotation_x, -90, 90)
		rotation_degrees = Vector3(rotation_x, rotation_y, 0)

func _process(delta):
	# Cancelar captura del mouse al presionar "ui_cancel"
	if Input.is_action_just_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	# Movimiento con teclas de flecha
	var movement = Vector3()
	if Input.is_action_pressed("ui_up"):
		movement.z -= 1
	if Input.is_action_pressed("ui_down"):
		movement.z += 1
	if Input.is_action_pressed("ui_left"):
		movement.x -= 1
	if Input.is_action_pressed("ui_right"):
		movement.x += 1

	# Aplica movimiento
	movement = movement.normalized() * move_speed * delta
	translate(movement)

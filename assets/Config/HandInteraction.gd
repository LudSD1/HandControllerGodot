extends Node3D

@export var interaction_area: Area3D

var interactable_objects: Array = []
var held_object: Node3D = null
enum HandState { OPEN, CLOSING, GRABBING, RELEASING }
var hand_state: HandState = HandState.OPEN

func _ready() -> void:
	# Usa Callable en lugar de pasar un String
	interaction_area.connect("body_entered", Callable(self, "_on_body_entered"))
	interaction_area.connect("body_exited", Callable(self, "_on_body_exited"))

func _on_body_entered(body: Node) -> void:
	if body.has_method("is_interactable") and body.is_interactable():
		interactable_objects.append(body)
	
func _on_body_exited(body: Node) -> void:
	interactable_objects.erase(body)

func process_hand_state(is_hand_closed: bool) -> void:
	if hand_state == HandState.OPEN and is_hand_closed and interactable_objects.size() > 0:
		grab_object(interactable_objects[0])
	elif hand_state == HandState.GRABBING and not is_hand_closed:
		release_object()

func grab_object(object: Node3D) -> void:
	hand_state = HandState.GRABBING
	held_object = object
	held_object.set_parent(self)
	held_object.position = Vector3.ZERO

func release_object() -> void:
	if held_object:
		hand_state = HandState.RELEASING
		held_object.set_parent(get_parent())
		held_object = null
		hand_state = HandState.OPEN

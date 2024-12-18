extends Node3D

# Variable para saber si el objeto está siendo agarrado
var is_grabbed: bool = false

# Llamada cuando la mano agarra el objeto
func grab(hand: Node):
	is_grabbed = true
	self.set_parent(hand)  # Hacer que el objeto sea hijo de la mano
	self.position = Vector3.ZERO  # Alinear con la mano

# Llamada cuando la mano suelta el objeto
func release():
	is_grabbed = false
	self.set_parent(null)  # Quitar de la mano

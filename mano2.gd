extends Node3D

var socket: WebSocketPeer
var skeleton: Skeleton3D
var hand_root: Node3D
var finger_bones = {
	"thumb": "Hueso.004",
	"index": "Hueso.013",
	"middle": "Hueso.008",
	"ring": "Hueso.018",
	"pinky": "Hueso.023"
}
var finger_states = {
	"thumb": 0,
	"index": 0,
	"middle": 0,
	"ring": 0,
	"pinky": 0
}
var max_rotation = PI / -2  # Maximum rotation (90 degrees)

var original_transforms = {}

func _ready():
	hand_root = self  # Assuming this script is attached to the "mano" node
	skeleton = $Esqueleto/Skeleton3D  # Adjust this path if necessary
	
	if skeleton == null:
		print("Skeleton not found")
		return
	
	for finger in finger_bones.keys():
		var bone_name = finger_bones[finger]
		var bone_index = skeleton.find_bone(bone_name)
		if bone_index != -1:
			original_transforms[bone_name] = skeleton.get_bone_global_pose(bone_index)
	
	socket = WebSocketPeer.new()
	var err = socket.connect_to_url("ws://192.168.1.214:81")
	if err != OK:
		print("Error attempting to connect: ", err)
	else:
		print("Attempting to connect...")

func _process(delta):
	socket.poll()
	var state = socket.get_ready_state()
	
	match state:
		WebSocketPeer.STATE_OPEN:
			while socket.get_available_packet_count() > 0:
				var packet = socket.get_packet()
				process_hand_data(packet.get_string_from_utf8())
		WebSocketPeer.STATE_CLOSING:
			# Keep reading packets to properly close.
			pass
		WebSocketPeer.STATE_CLOSED:
			var code = socket.get_close_code()
			var reason = socket.get_close_reason()
			print("WebSocket closed with code: %d, reason %s. Clean: %s" % [code, reason, code != -1])
			set_process(false)  # Stop processing.

func process_hand_data(data: String):
	var data_parts = data.split(";")
	for part in data_parts:
		if part.begins_with("acelX:"):
			var accel_data = part.split(",")
			var accel_x = float(accel_data[0].split(":")[1])
			var accel_y = float(accel_data[1].split(":")[1])
			var accel_z = float(accel_data[2].split(":")[1])
			apply_acceleration(accel_x, accel_y, accel_z)
		elif part.begins_with("gyroX:"):
			var gyro_data = part.split(",")
			var gyro_x = float(gyro_data[0].split(":")[1])
			var gyro_y = float(gyro_data[1].split(":")[1])
			var gyro_z = float(gyro_data[2].split(":")[1])
			rotate_hand(gyro_x, gyro_y, gyro_z)
		elif "," in part:
			var finger_data = part.split(",")
			if finger_data.size() == 2:
				var finger_index = int(finger_data[0])
				var state = int(finger_data[1])
				update_finger_state(finger_index, state)

func apply_acceleration(accel_x: float, accel_y: float, accel_z: float):
	# You can use acceleration data to modify hand position if needed
	# For now, we'll just print it
	print("Acceleration: ", accel_x, ", ", accel_y, ", ", accel_z)


func rotate_hand(gyro_x: float, gyro_y: float, gyro_z: float):
	print("Rotating hand: ", gyro_x, ", ", gyro_y, ", ", gyro_z)
	var sensitivity = 0.001  # Ajusta este valor según la sensibilidad deseada
	var rotation_vector = Vector3(gyro_x, gyro_y, gyro_z) * sensitivity
	# Limita la rotación en los ejes X, Y, Z para que sea más realista
	var max_rotation_x = deg_to_rad(90)  # 90 grados en el eje X
	var max_rotation_y = deg_to_rad(30)  # 30 grados en el eje Y
	var max_rotation_z = deg_to_rad(90)  # 90 grados en el eje Z
	# Rotar en el eje X (flexión/extensión)
	var new_rotation_x = clamp(hand_root.rotation.x + rotation_vector.x, -max_rotation_x, max_rotation_x)
	hand_root.rotation.x = new_rotation_x
	# Rotar en el eje Y (abducción/aducción)
	var new_rotation_y = clamp(hand_root.rotation.y + rotation_vector.y, -max_rotation_y, max_rotation_y)
	hand_root.rotation.y = new_rotation_y
	# Rotar en el eje Z (pronación/supinación)
	var new_rotation_z = clamp(hand_root.rotation.z + rotation_vector.z, -max_rotation_z, max_rotation_z)
	hand_root.rotation.z = new_rotation_z


func update_finger_state(finger_index: int, state: int):
	var finger_name = ""
	match finger_index:
		1: finger_name = "thumb"
		2: finger_name = "index"
		3: finger_name = "middle"
		4: finger_name = "ring"
		5: finger_name = "pinky"
	
	if finger_name != "":
		finger_states[finger_name] = state
		if state == 1:
			rotate_finger(finger_name)
		else:
			reset_finger(finger_name)

func rotate_finger(finger: String):
	if finger in finger_bones:
		var bone_name = finger_bones[finger]
		var bone_index = skeleton.find_bone(bone_name)
		if bone_index != -1:
			var rotation = max_rotation
			var old_transform = skeleton.get_bone_global_pose(bone_index)
			var new_transform = old_transform

			var rotation_axis = Vector3(1, 0, 0)  # Default axis
			
			match finger:
				"thumb": rotation_axis = Vector3(0, 1, 0)
				"index": rotation_axis = Vector3(1, 0, 0)
				"middle": rotation_axis = Vector3(1, 0, 0)
				"ring": rotation_axis = Vector3(1, 0, 0)
				"pinky": rotation_axis = Vector3(1, -1, 0).normalized()
			
			new_transform.basis = old_transform.basis.rotated(rotation_axis, rotation)
			skeleton.set_bone_global_pose_override(bone_index, new_transform, 1.0, true)
			print("Rotated %s to %f" % [finger, rotation])

func reset_finger(finger: String):
	if finger in finger_bones:
		var bone_name = finger_bones[finger]
		var bone_index = skeleton.find_bone(bone_name)
		if bone_index != -1:
			var reset_transform = original_transforms[bone_name]
			skeleton.set_bone_global_pose_override(bone_index, reset_transform, 1.0, true)
			print("Reset %s" % [finger])

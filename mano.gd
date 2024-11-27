extends Node3D
@export var HandControl = preload("res://mano.gd")


const SENSITIVITY_GYRO: float = 0.09
const SENSITIVITY_ACCEL = 0.09  # Reduced sensitivity
const FINGER_ROTATION_SPEED = 0.09
const RECONNECT_DELAY = 5.0

var camera: Camera3D

# Position constraints
#const POSITION_LIMITS = {
#	"min": Vector3(-0.15, -0.15, -0.15),
#	"max": Vector3(0.15, 0.15, 0.15)
#}

const POSITION_LIMITS = {
	"min": Vector3(-0.5, -0.8, -0.2),  # Aumentado para permitir más movimiento lateral y vertical
	"max": Vector3(0.5, 0.8, 0.2)    # z es menor para mantener= la mano a una distancia cómoda
}

var initial_position: Vector3
var smooth_position: Vector3
var velocity: Vector3
# Movement smoothing
const POSITION_SMOOTHING = 0.90  # Higher = smoother
const ROTATION_SMOOTHING = 0.95   # Higher = smoother

# Add rotation limits to prevent excessive spinning
const MAX_ROTATION_RATE = PI  # Maximum rotation rate in radians per second
const GYRO_DEADZONE = 0.01      # Ignore very small rotations
const MAX_ROTATION_ANGLE = PI

const VELOCITY_DAMPING = 0.97
const ACCELERATION_DEADZONE = 15  # Increased from 100
const ACCEL_DEADZONE = 15

class HandBone:
	var name: String
	var bone_index: int
	var rotation_axis: Vector3
	var current_rotation: float
	var target_rotation: float
	var original_transform: Transform3D
	
	func _init(n: String, idx: int, axis: Vector3, ):
		name = n
		bone_index = idx
		rotation_axis = axis
		current_rotation = 0.0
		target_rotation = 0.0

class HandController:
	var socket: WebSocketPeer
	var skeleton: Skeleton3D
	var hand_root: Node3D
	var bones: Dictionary
	var last_connection_attempt: float
	var is_connecting: bool
	var camera: Camera3D
	var current_rotation: Quaternion = Quaternion.IDENTITY
	var target_rotation: Quaternion = Quaternion.IDENTITY
	var accumulated_rotation: Vector3 = Vector3.ZERO
	
	# Movement smoothing variables
	var velocity: Vector3 = Vector3.ZERO
	var smooth_position: Vector3 = Vector3.ZERO
	var smooth_rotation: Vector3 = Vector3.ZERO
	var initial_position: Vector3
	
	var FINGER_MAPPING = {
		"thumb": {"bone": "Hueso.004", "axis": Vector3(0, 1, 0)},
		"index": {"bone": "Hueso.013", "axis": Vector3(1, 0, 0)},
		"middle": {"bone": "Hueso.008", "axis": Vector3(1, 0, 0)},
		"ring": {"bone": "Hueso.018", "axis": Vector3(1, 0, 0)},
		"pinky": {"bone": "Hueso.023", "axis": Vector3(1, -1, 0).normalized()}
	}
	
	func _init(root: Node3D, skel: Skeleton3D, cam: Camera3D):
		hand_root = root
		skeleton = skel
		camera = cam
		socket = WebSocketPeer.new()
		bones = {}
		is_connecting = false
		initial_position = root.position
		velocity = Vector3.ZERO
		smooth_position = initial_position
		setup_bones()
	
	func setup_bones() -> void:
		for finger in FINGER_MAPPING:
			var data = FINGER_MAPPING[finger]
			var bone_index = skeleton.find_bone(data.bone)
			if bone_index != -1:
				var bone = HandBone.new(data.bone, bone_index, data.axis)
				bone.original_transform = skeleton.get_bone_global_pose(bone_index)
				bones[finger] = bone
	
	
	func reset_rotation() -> void:
		current_rotation = Quaternion.IDENTITY
		target_rotation = Quaternion.IDENTITY
		hand_root.quaternion = Quaternion.IDENTITY

	func reset_position() -> void:
		hand_root.position = initial_position
		smooth_position = initial_position
		velocity = Vector3.ZERO
		reset_rotation()
	
	func connect_to_server(url: String) -> void:
		if is_connecting:
			return
			
		is_connecting = true
		last_connection_attempt = Time.get_ticks_msec()
		
		var err = socket.connect_to_url(url)
		if err != OK:
			print("Connection error: ", err)
			is_connecting = false
		else:
			print("Attempting to connect to ", url)
	
	func process_socket(delta: float) -> void:
		if socket == null:
			return
			
		socket.poll()
		var state = socket.get_ready_state()
		
		match state:
			WebSocketPeer.STATE_OPEN:
				while socket.get_available_packet_count() > 0:
					var packet = socket.get_packet()
					process_hand_data(packet.get_string_from_utf8(), delta)
			
			WebSocketPeer.STATE_CLOSING:
				pass
				
			WebSocketPeer.STATE_CLOSED:
				var current_time = Time.get_ticks_msec()
				if current_time - last_connection_attempt >= RECONNECT_DELAY * 1000:
					is_connecting = false
					reset_position()  # Reset position when connection is lost

	func process_hand_data(data: String, delta: float) -> void:
		var json = JSON.parse_string(data)
		if json == null:
			print("Invalid JSON data received")
			return
		
		# Process finger data
		if "fingers" in json:
			for change in json.fingers:
				if "id" in change and "state" in change:
					update_finger_state(change.id, change.state)
		
		# Process MPU data
		if "mpu" in json:
			var mpu = json.mpu
			if "gx" in mpu and "gy" in mpu and "gz" in mpu:
				apply_rotation(mpu.gx, mpu.gy, mpu.gz, delta)
			if "ax" in mpu and "ay" in mpu and "az" in mpu:
				apply_acceleration(mpu.ax, mpu.ay, mpu.az)
	
	func update_finger_state(finger_id: int, state: int) -> void:
		var finger_name = ""
		match finger_id:
			1: finger_name = "thumb"
			2: finger_name = "index"
			3: finger_name = "middle"
			4: finger_name = "ring"
			5: finger_name = "pinky"
		
		if finger_name in bones:	
			var bone = bones[finger_name]
			bone.target_rotation = -PI/2 if state == 1 else 0.0
	
	func apply_rotation(gx: float, gy: float, gz: float, delta: float) -> void:
		# Apply deadzone to reduce drift
		
		if abs(gx) < GYRO_DEADZONE: gx = 0
		if abs(gy) < GYRO_DEADZONE: gy = 0
		if abs(gz) < GYRO_DEADZONE: gz = 0
		
		
		var rotation_rate = Vector3(gx, gy, gz) * SENSITIVITY_GYRO * delta
		
		
		 # Accumulate rotation
		accumulated_rotation += rotation_rate
		accumulated_rotation.x = clamp(accumulated_rotation.x, -PI/2, PI/2)
		accumulated_rotation.y = clamp(accumulated_rotation.y, -PI/2, PI/2)
		accumulated_rotation.z = clamp(accumulated_rotation.z, -PI/2, PI/4)

		 # Create rotation quaternion from accumulated rotation
		
		target_rotation = Quaternion.from_euler(accumulated_rotation)
		
		# Smooth the rotation
		
		current_rotation = current_rotation.slerp(target_rotation, 1.0 - ROTATION_SMOOTHING)
		
		# Apply the smoothed rotation to the hand root
		
		hand_root.quaternion = current_rotation
		
		# Add rotation wrapping to handle full 180° rotations
		
		if accumulated_rotation.length() >= MAX_ROTATION_ANGLE:
			# Reset accumulated rotation while preserving direction
			accumulated_rotation = accumulated_rotation.normalized() * (MAX_ROTATION_ANGLE * 0.9)

		
		# Clamp rotation rate
		
		rotation_rate = rotation_rate.clamp(
			Vector3(-MAX_ROTATION_RATE, -MAX_ROTATION_RATE, -MAX_ROTATION_RATE),
			Vector3(MAX_ROTATION_RATE, MAX_ROTATION_RATE, MAX_ROTATION_RATE)
		)
		# Create rotation quaternion
		var rotation = Quaternion.from_euler(rotation_rate)
		target_rotation = target_rotation * rotation
		# Smooth the rotation
		current_rotation = current_rotation.slerp(target_rotation, 1.0 - ROTATION_SMOOTHING)
		# Apply the smoothed rotation to the hand root
		hand_root.quaternion = current_rotation
	
	func apply_acceleration(ax: float, ay: float, az: float) -> void:
		# Apply dead zone to reduce drift
	
		const MICRO_DEADZONE = 0.05  # Zona muerta más sensible
	
	# Filtrado de aceleración más suave
	
		if abs(ax) < MICRO_DEADZONE: ax = 0
	
		if abs(ay) < MICRO_DEADZONE: ay = 0
	
		if abs(az) < MICRO_DEADZONE: az = 0
		
		var acceleration = Vector3(ax, ay, az) * SENSITIVITY_ACCEL

 	# Física de movimiento más natural
	
		var inertia_factor = 0.3  # Factor de inercia
	
		var damping_factor = 0.95  # Amortiguación
	
		velocity = (velocity + acceleration) * damping_factor
	
	# Limitar velocidad máxima
	
		var max_velocity = Vector3(0.5, 0.5, 0.5)
	
		velocity = velocity.clamp(-max_velocity, max_velocity)
	
	# Movimiento suave con interpolación
	
		var target_position = smooth_position + velocity * inertia_factor
	
	# Limitación de movimiento más realista
	
		target_position = target_position.clamp(
		initial_position + POSITION_LIMITS.min, 
		initial_position + POSITION_LIMITS.max
	
		)
	
	# Interpolación más suave
	
		smooth_position = smooth_position.lerp(target_position, 0.2)
	
	# Aplicar movimiento gradual
	
		hand_root.position = smooth_position
	
	# Reducción gradual de movimiento
	
		if velocity.length() < 0.01:
		
				velocity *= 0.8  # Desaceleración más natural


	func is_at_limit() -> bool:
		var pos = hand_root.position - initial_position
	
		return (
			pos.x <= POSITION_LIMITS.min.x or pos.x >= POSITION_LIMITS.max.x or
			pos.y <= POSITION_LIMITS.min.y or pos.y >= POSITION_LIMITS.max.y or
			pos.z <= POSITION_LIMITS.min.z or pos.z >= POSITION_LIMITS.max.z
	)




		
	func update_bones(delta: float) -> void:
		for finger in bones:
			var bone = bones[finger]
			if bone.current_rotation != bone.target_rotation:
				bone.current_rotation = lerp(bone.current_rotation, 
										  bone.target_rotation, 
										  FINGER_ROTATION_SPEED)
				
				var new_transform = bone.original_transform
				new_transform.basis = new_transform.basis.rotated(
					bone.rotation_axis, 
					bone.current_rotation
				)
				
				skeleton.set_bone_global_pose_override(
					bone.bone_index,
					new_transform,
					1.0,
					true
				)

var controller: HandController




func _ready() -> void:
	camera = get_parent()
	initial_position = position
	smooth_position = initial_position
	velocity = Vector3.ZERO
	
	
	
	
	var skeleton_node = $Esqueleto/Skeleton3D  # Ajusta esta ruta según tu árbol de nodos
	if skeleton_node == null:
		push_error("Skeleton3D node not found!")
		return
	controller = HandController.new(self, skeleton_node, camera)
	controller.connect_to_server(ConnectionManager.last_url)
	position = camera.position + (-camera.global_transform.basis.z * 1.5)
	initial_position = position
	smooth_position = initial_position



func _process(delta: float) -> void:
	if controller != null:
		controller.process_socket(delta)
		controller.update_bones(delta)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"): # ESC key
		get_tree().change_scene_to_file("res://Interface.tscn")

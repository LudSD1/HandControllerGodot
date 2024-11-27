extends Node3D

# Signals
signal connection_established
signal connection_lost
signal tracking_started
signal tracking_lost

# Preloaded resources
@export var HandControl = preload("res://mano.gd")

var FINGER_MAPPING = {
	"thumb": {
		"bone": "Hueso.004",
		"axis": Vector3(0, 1, 0),
		"limits": {"min": -PI/3, "max": 0}
	},
	"index": {
		"bone": "Hueso.013",
		"axis": Vector3(1, 0, 0),
		"limits": {"min": -PI/2, "max": 0}
	},
	"middle": {
		"bone": "Hueso.008",
		"axis": Vector3(1, 0, 0),
		"limits": {"min": -PI/2, "max": 0}
	},
	"ring": {
		"bone": "Hueso.018",
		"axis": Vector3(1, 0, 0),
		"limits": {"min": -PI/2, "max": 0}
	},
	"pinky": {
		"bone": "Hueso.023",
		"axis": Vector3(1, -1, 0).normalized(),
		"limits": {"min": -PI/2, "max": 0}
	}
}
var initial_position: Vector3
var smooth_position: Vector3
var velocity: Vector3


# Constants
const SENSITIVITY = {
	"GYRO": 0.05,
	"ACCEL": 0.8,
	"FINGER": 0.09,
	"FOLLOW": 5.0  # New following sensitivity
}

const SMOOTHING = {
	"POSITION": 0.90,
	"ROTATION": 0.95,
	"BONE": 0.85  # New bone interpolation smoothing
}

const LIMITS = {
	"POSITION": {
		"MIN": Vector3(-1.5, -1.2, -0.5),
		"MAX": Vector3(1.5, 1.2, 0.05)
	},
	"ROTATION": {
		"MAX_RATE": PI,
		"MAX_ANGLE": PI
	},
	"FOLLOW_DISTANCE": {
		"MIN": 0.3,
		"MAX": 2.0
	}
}

const DEADZONES = {
	"GYRO": 0.01,
	"ACCEL": 8.0,
	"VELOCITY": 0.01,
	"POSITION": 0.001  # New position change deadzone
}

const DAMPING = {
	"VELOCITY": 0.97,
	"ROTATION": 0.98  # New rotation damping
}

const RECONNECT_DELAY = 5.0
const MAX_RECONNECT_ATTEMPTS = 3



class HandBone:
	var name: String
	var bone_index: int
	var rotation_axis: Vector3
	var current_rotation: float
	var target_rotation: float
	var original_transform: Transform3D
	var min_angle: float
	var max_angle: float
	
	func _init(n: String, idx: int, axis: Vector3, limits: Dictionary):
		name = n
		bone_index = idx
		rotation_axis = axis
		current_rotation = 0.0
		target_rotation = 0.0
		min_angle = limits.get("min", -PI/2)
		max_angle = limits.get("max", 0)

class HandController:
	# Core components
	var socket: WebSocketPeer
	var skeleton: Skeleton3D
	var hand_root: Node3D
	var camera: Camera3D
	var FINGER_MAPPING : Dictionary
	var HandControl
	# State tracking
	var bones: Dictionary = {}
	var last_connection_attempt: float
	var is_connecting: bool = false
	var reconnect_attempts: int = 0
	var last_successful_data: float = 0
	
	# Motion tracking
	var current_rotation: Quaternion = Quaternion.IDENTITY
	var target_rotation: Quaternion = Quaternion.IDENTITY
	var accumulated_rotation: Vector3 = Vector3.ZERO
	var velocity: Vector3 = Vector3.ZERO
	var smooth_position: Vector3
	var smooth_rotation: Vector3 = Vector3.ZERO
	var initial_position: Vector3
	var last_valid_position: Vector3
	
	# New tracking state
	var is_tracking: bool = false
	var tracking_confidence: float = 0.0
	var tracking_timeout: float = 1.0  # Seconds without data before considered lost
	
	func _init(root: Node3D, skel: Skeleton3D, cam: Camera3D):
		hand_root = root
		skeleton = skel
		camera = cam
		socket = WebSocketPeer.new()
		initial_position = root.position
		smooth_position = initial_position
		last_valid_position = initial_position
		setup_bones()
		
	func setup_bones() -> void:
		for finger_name in FINGER_MAPPING:
			var data = FINGER_MAPPING[finger_name]
			var bone_index = skeleton.find_bone(data["bone"])  # Access property with bracket notation
			if bone_index != -1:
				bones[finger_name] = HandBone.new(
				data["bone"],
				bone_index,
				data["axis"],
				data["limits"]
			)
			
			bones[finger_name].original_transform = skeleton.get_bone_global_pose(bone_index)


	# New method to handle tracking state
	func update_tracking_state(delta: float) -> void:
		var current_time = Time.get_ticks_msec() / 1000.0
		var time_since_data = current_time - last_successful_data
		
		if time_since_data > tracking_timeout:
			if is_tracking:
				is_tracking = false
				hand_root.emit_signal("tracking_lost")
		else:
			if not is_tracking:
				is_tracking = true
				hand_root.emit_signal("tracking_started")
	
	# Enhanced position update with camera following
	func _update_position(delta) -> void:
		if velocity.length() <= DEADZONES.VELOCITY:
			return
		
		var camera_forward = -camera.global_transform.basis.z
		var target_distance = clamp(
			smooth_position.distance_to(camera.position),
			LIMITS.FOLLOW_DISTANCE.MIN,
			LIMITS.FOLLOW_DISTANCE.MAX
		)
		
		var ideal_position = camera.position + (camera_forward * target_distance)
		var new_position = smooth_position.lerp(
			ideal_position + velocity,
			delta * SENSITIVITY.FOLLOW
		)
		
		var camera_space_position = camera.global_transform.inverse() * new_position
		camera_space_position = camera_space_position.clamp(
			LIMITS.POSITION.MIN,
			LIMITS.POSITION.MAX
		)
		
		new_position = camera.global_transform * camera_space_position
		
		# Only update if movement is significant
		if new_position.distance_to(smooth_position) > DEADZONES.POSITION:
			last_valid_position = smooth_position
			smooth_position = smooth_position.lerp(new_position, 1.0 - SMOOTHING.POSITION)
			hand_root.position = smooth_position

	func reset_position() -> void:
		hand_root.position = initial_position
		smooth_position = initial_position
		velocity = Vector3.ZERO
		reset_rotation()

	func reset_rotation() -> void:
		current_rotation = Quaternion.IDENTITY
		target_rotation = Quaternion.IDENTITY
		hand_root.quaternion = Quaternion.IDENTITY


	#func update_finger_state(finger_id: int, state: float) -> void:
	## Convert finger ID to finger name using a more robust mapping
	#
		#var finger_name = match_finger_id_to_name(finger_id)
		#if finger_name.is_empty():
			#return  # Invalid finger ID
	#
	## Get the bone data for this finger
		#var bone = bones.get(finger_name)
		#
		#if not bone:
			#return
	#
	## Ensure state is between 0 and 1
		#state = clamp(state, 0.0, 1.0)
	#
	## Calculate target rotation with more nuanced interpolation
	#
		#var target_angle = lerp(
			#bone.min_angle,  # Fully open position
			#bone.max_angle,  # Fully closed position
			#state
		#)
	#
	## Apply advanced smoothing with optional exponential curve
	#
		#bone.target_rotation = lerp_angle(
		#
			#bone.current_rotation, 
		#
			#target_angle, 
		#
			#1.0 - SMOOTHING.BONE
		#)
	#
	## Optional: Add non-linear response for more natural movement
	#
		#var curved_rotation = ease_rotation(bone.target_rotation, 2.0)
	#
	## Create rotation transform
	#
		#var rotation = Transform3D().rotated(
			#bone.rotation_axis,
			#curved_rotation
		#)
	#
	## Apply rotation while preserving original transform
		#skeleton.set_bone_global_pose(
			#bone.bone_index,
			#bone.original_transform * rotation
		#)
	## Apply rotation while preserving original transform
	#
		#skeleton.set_bone_global_pose(
			#bone.bone_index,
			#bone.original_transform * rotation
		#)



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


	func match_finger_id_to_name(finger_id: int) -> String:
		match finger_id:
			1: return "thumb"
			2: return "index"
			3: return "middle"
			4: return "ring"
			5: return "pinky"
			_: return ""  # Invalid finger ID


# Optional: Non-linear rotation easing function

	func ease_rotation(rotation: float, curve: float = 2.0) -> float:
	# Applies a power curve to the rotation for more natural movement
		return sign(rotation) * pow(abs(rotation), curve)

# Optional: Angle interpolation with smoother transitions

	func lerp_angle(from: float, to: float, weight: float) -> float:
		var difference = fmod(to - from, TAU)
		var distance = fmod(2.0 * difference, TAU) - difference
		return from + distance * weight

	func apply_rotation(gx: float, gy: float, gz: float, delta: float) -> void:
		# Apply deadzone to reduce drift
		
		if abs(gx) < DEADZONES['GYRO']: gx = 0
		if abs(gy) < DEADZONES['GYRO']: gy = 0
		if abs(gz) < DEADZONES['GYRO']: gz = 0
		
		
		var rotation_rate = Vector3(gx, gy, gz) * SENSITIVITY['GYRO'] * delta
		
		
		 # Accumulate rotation
		accumulated_rotation += rotation_rate
		accumulated_rotation.x = clamp(accumulated_rotation.x, -PI/2, PI/2)
		accumulated_rotation.y = clamp(accumulated_rotation.y, -PI/2, PI/2)
		accumulated_rotation.z = clamp(accumulated_rotation.z, -PI/2, PI/4)

		 # Create rotation quaternion from accumulated rotation
		
		target_rotation = Quaternion.from_euler(accumulated_rotation)
		
		# Smooth the rotation
		
		current_rotation = current_rotation.slerp(target_rotation, 1.0 - SMOOTHING['ROTATION'])
		
		# Apply the smoothed rotation to the hand root
		
		hand_root.quaternion = current_rotation
		
		# Add rotation wrapping to handle full 180° rotations
		
		if accumulated_rotation.length() >= LIMITS['ROTATION']['MAX_RATE']:
			# Reset accumulated rotation while preserving direction
			accumulated_rotation = accumulated_rotation.normalized() * (LIMITS['ROTATION']['MAX_RATE'] * 0.9)

		
		# Clamp rotation rate
		
		rotation_rate = rotation_rate.clamp(
			Vector3(-LIMITS['ROTATION']['MAX_RATE'], -LIMITS['ROTATION']['MAX_RATE'], -LIMITS['ROTATION']['MAX_RATE']),
			Vector3(LIMITS['ROTATION']['MAX_RATE'], LIMITS['ROTATION']['MAX_RATE'], LIMITS['ROTATION']['MAX_RATE'])
		)
		# Create rotation quaternion
		var rotation = Quaternion.from_euler(rotation_rate)
		target_rotation = target_rotation * rotation
		# Smooth the rotation
		current_rotation = current_rotation.slerp(target_rotation, 1.0 -SMOOTHING['ROTATION'])
		# Apply the smoothed rotation to the hand root
		hand_root.quaternion = current_rotation
		

	func apply_acceleration(ax: float, ay: float, az: float) -> void:
		# Apply dead zone to reduce drift
		if abs(ax) < DEADZONES['ACCEL']: ax = 0
		if abs(ay) < DEADZONES['ACCEL']: ay = 0
		if abs(az) < DEADZONES['ACCEL']: az = 0
		
		var acceleration = Vector3(-ax, ay, az) * SENSITIVITY['ACCEL']
		var accel_magnitude = acceleration.length()
		
		
		# Ajustar la sensibilidad basada en la magnitud del movimiento
	
		var adjusted_sensitivity = SENSITIVITY['ACCEL']
	
		if accel_magnitude > 0.5:  # Para movimientos más rápidos
			adjusted_sensitivity *= 1.5
		elif accel_magnitude < 0.2:  # Para movimientos más suaves
			adjusted_sensitivity *= 0.8
		acceleration *= adjusted_sensitivity
		
		
		# Update velocity with smoothing
		if acceleration.length() > 0.05:  # 0.01 es un umbral pequeño para eliminar el movimiento en reposo
			velocity = velocity.lerp(acceleration, 1.0 - SMOOTHING['POSITION']) * DAMPING['VELOCITY']
			#velocity = velocity.lerp(acceleration, 1.0 - POSITION_SMOOTHING) * VELOCITY_DAMPING
		velocity *= DAMPING['VELOCITY']
		
			# Actualizar posición si la velocidad es significativa
		if velocity.length() > 0.01:  # Evita movimiento cuando la velocidad es mínima
			var camera_forward = camera.global_transform.basis.z * -1
			var new_position = smooth_position + velocity + camera_forward * 1
			var camera_space_position = camera.global_transform.inverse() * new_position 
   
			camera_space_position = camera_space_position.clamp(LIMITS['POSITION']['MIN'], LIMITS['POSITION']['MAX'])
		# Convertir de vuelta al espacio global
			new_position = camera.global_transform * camera_space_position
		
		# Suavizar el movimiento y actualizar la posición de la mano
			smooth_position = smooth_position.lerp(new_position, 1.0 - SMOOTHING['POSITION'])
			hand_root.position = smooth_position
		elif acceleration.length() > 0.01:
			var small_movement = acceleration.normalized() * 0.01
			smooth_position = smooth_position.lerp(
				hand_root.position + small_movement,
				1.0 - SMOOTHING['POSITION']
			)
			hand_root.position = smooth_position

	# Resetear velocidad si se alcanzan los límites o si la aceleración es baja
		if is_at_limit() or acceleration.length() < 0.01:
			velocity = Vector3.ZERO
		elif acceleration.length() < 0.1:  # Add this check	
			# Aplicar un pequeño movimiento incluso con baja aceleración
			velocity = velocity.lerp(Vector3(0.01, 0.01, 0.01), 1.0 - SMOOTHING['POSITION'])
			smooth_position = smooth_position.lerp(hand_root.position + velocity, 1.0 - SMOOTHING['POSITION'])
			hand_root.position = smooth_position

	func is_at_limit() -> bool:
		var pos = hand_root.position - initial_position
	
		return (
			pos.x <= LIMITS['POSITION']['MIN'].x or pos.x >= LIMITS['POSITION']['MAX'].x or
			pos.y <= LIMITS['POSITION']['MIN'].y or pos.y >= LIMITS['POSITION']['MAX'].y or
			pos.z <= LIMITS['POSITION']['MIN'].z or pos.z >= LIMITS['POSITION']['MAX'].z
	)



	# Enhanced bone update with interpolation
	func update_bones(delta: float) -> void:
		for bone in bones.values():
			if bone.current_rotation != bone.target_rotation:
				var target = clamp(
					bone.target_rotation,
					bone.min_angle,
					bone.max_angle
				)
				
				bone.current_rotation = lerp(
					bone.current_rotation,
					target,
					SENSITIVITY['FINGER'] * delta
				)
				
				var new_transform = bone.original_transform
				new_transform.basis = new_transform.basis.rotated(
					bone.rotation_axis,
					bone.current_rotation
				)
				
				# Interpolate between current and target pose
				var current_pose = skeleton.get_bone_global_pose(bone.bone_index)
				var target_pose = new_transform
				var interpolated_pose = current_pose.interpolate_with(
					target_pose,
					1.0 - SMOOTHING['BONE']
				)
				
				skeleton.set_bone_global_pose_override(
					bone.bone_index,
					interpolated_pose,
					1.0,
					true
				)

	# Enhanced error recovery

	#func _handle_reconnection() -> void:
		#var current_time = Time.get_ticks_msec()
	#
	## Check if enough time has passed since the last attempt
		#if current_time - last_connection_attempt >= RECONNECT_DELAY * 1000:
			#if reconnect_attempts < MAX_RECONNECT_ATTEMPTS:
				#is_connecting = false
				#reconnect_attempts += 1
			## Attempt to reconnect
				#if has_method("connect_to_server"):
					#connect_to_server(ConnectionManager.last_url)
				#else:
					#push_error("connect_to_server() method not found!")
			#else:
			## Reset the hand and log a warning after exceeding attempts
				#if has_method("reset_hand"):
					#reset_hand()
				#else:
					#push_error("reset_hand() method not found!")
				#push_warning("Max reconnection attempts reached")

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


	# New method to validate position changes
	func _validate_position_change(new_pos: Vector3) -> bool:
		var distance = new_pos.distance_to(last_valid_position)
		var max_allowed_distance = LIMITS.FOLLOW_DISTANCE.MAX * 1.5
		return distance <= max_allowed_distance

# Main node implementation
var controller: HandController
var camera: Camera3D

func _ready() -> void:
	camera = get_parent()
	initial_position = position
	smooth_position = initial_position
	
	var skeleton_node = $Esqueleto/Skeleton3D
	if not skeleton_node:
		push_error("Skeleton3D node not found!")
		return
	
	controller = HandController.new(self, skeleton_node, camera)
	controller.connect_to_server(ConnectionManager.last_url)
	position = camera.position + (-camera.global_transform.basis.z * 1.5)
	initial_position = position
	smooth_position = initial_position




func _process(delta: float) -> void:
	if controller:
		controller.update_tracking_state(delta)
		controller.process_socket(delta)
		controller.update_bones(delta)




func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().change_scene_to_file("res://Interface.tscn")

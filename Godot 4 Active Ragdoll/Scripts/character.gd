extends Node3D

# movement/walking/jumping stuff
const JUMP_STRENGTH = 70
const SPEED = 50
@export var sprint_speed_multiplier: float = 1.75 
const DAMPING = 0.9
@onready var on_floor_left = $"Physical/Armature/Skeleton3D/Physical Bone LLeg2/OnFloorLeft" 
@onready var on_floor_right = $"Physical/Armature/Skeleton3D/Physical Bone RLeg2/OnFloorRight" 
@onready var jump_timer = $Physical/JumpTimer 
var can_jump = true
var is_on_floor = false
var walking = false 

# Missing physics mechanics parameters
@export var impact_threshold: float = 22.0     
@export var dive_force: float = 80.0          
@export var dive_upward_bias: float = 50.0    
@export var swing_throw_multiplier: float = 5.0 

var knockout_timer: float = 0.0
var is_diving: bool = false

# spring stuff
@export var angular_spring_stiffness: float = 4000.0
@export var angular_spring_damping: float = 80.0
@export var max_angular_force: float = 9999.0

var physics_bones = [] 

# turn it into ragdoll
@export var ragdoll_mode := false

@onready var physical_skel : Skeleton3D = $Physical/Armature/Skeleton3D
@onready var animated_skel : Skeleton3D = $Animated/Armature/Skeleton3D
@onready var camera_pivot = $CameraPivot
@onready var animation_tree = $Animated/AnimationTree
@onready var physical_bone_body : PhysicalBone3D = $"Physical/Armature/Skeleton3D/Physical Bone Body"

# grabbing related stuff
var active_arm_left = false
var active_arm_right = false
var grabbed_object = null
var grabbing_arm_left = false
var grabbing_arm_right = false
@onready var grab_joint_right = $Physical/GrabJointRight
@onready var grab_joint_left = $Physical/GrabJointLeft
@onready var physical_bone_l_arm_2 = $"Physical/Armature/Skeleton3D/Physical Bone LArm2"
@onready var physical_bone_r_arm_2 = $"Physical/Armature/Skeleton3D/Physical Bone RArm2"
@onready var l_grab_area = $"Physical/Armature/Skeleton3D/Physical Bone LArm2/LGrabArea"
@onready var r_grab_area = $"Physical/Armature/Skeleton3D/Physical Bone RArm2/RGrabArea"

var current_delta:float

# --- MULTIPLAYER PROPERTIES ---
@export var player_id: int = 1

# Cached network inputs sent from clients to the host
var network_dir: Vector3 = Vector3.ZERO
var network_sprint: bool = false
var network_jump_pressed: bool = false

func check_impact_knockout():
	if not multiplayer.is_server(): return # Only the server determines knockouts
	if not ragdoll_mode and physical_bone_body.linear_velocity.length() > impact_threshold:
		if on_floor_left.is_colliding() or on_floor_right.is_colliding():
			trigger_knockout()

func trigger_knockout():
	ragdoll_mode = true
	knockout_timer = 2.0 
	
	grabbing_arm_left = false
	grab_joint_left.node_a = NodePath()
	grab_joint_left.node_b = NodePath()
	grabbing_arm_right = false
	grab_joint_right.node_a = NodePath()
	grab_joint_right.node_b = NodePath()
	
func is_local_authority() -> bool:
	# Returns true only if this specific character belongs to this game window
	return name == str(multiplayer.get_unique_id())

func _ready():
	var cam = find_child("Camera3D", true, false)
	if cam:
		cam.current = false
	
	await get_tree().process_frame
	
	if multiplayer.is_server():
		if physical_skel:
			physical_bone_body.linear_velocity = Vector3.ZERO
			physical_bone_body.angular_velocity = Vector3.ZERO
			
			physical_skel.physical_bones_start_simulation()
			physics_bones = physical_skel.get_children().filter(func(x): return x is PhysicalBone3D)
	
	# THE FIX: Use our custom ownership check to claim the camera!
	if is_local_authority():
		if cam:
			cam.current = true
			print("[CHARACTER] Authority confirmed. Camera Activated.")

func _input(event):
	# Only collect input if this specific instance belongs to the local player window
	if not is_local_authority(): return

	# Spacebar to recover from ragdoll/knockout mode
	if ragdoll_mode and Input.is_action_just_pressed("jump"):
		# Force block the jump queue right here locally before it ever ships to the physics thread
		network_jump_pressed = false
		
		if multiplayer.is_server():
			request_wakeup() # Execute locally on server thread
		else:
			request_wakeup.rpc_id(1) # Send up to host from client machine
			
		get_viewport().set_input_as_handled()
		return

	# Manual ragdoll toggle key
	if Input.is_action_just_pressed("ragdoll"):
		if multiplayer.is_server():
			request_ragdoll_toggle() 
		else:
			request_ragdoll_toggle.rpc_id(1)

func _process(delta):
	if multiplayer.is_server() and ragdoll_mode:
		knockout_timer -= delta
		if knockout_timer <= 0.0 and physical_bone_body.linear_velocity.length() < 1.5:
			ragdoll_mode = false 
			is_diving = false # Safety fallback to clear dive lag
	
	# Keep bone aiming directions responsive locally
	var r = clamp((camera_pivot.rotation.x*2)/(PI)*2.1,-1,1)
	if active_arm_left or active_arm_right:
		animation_tree.set("parameters/grab_dir/blend_position",r)
	else:
		animation_tree.set("parameters/grab_dir/blend_position",0)

func _physics_process(delta):
	current_delta = delta
	
	# 1. CLIENT INPUT TRANSMISSION
	if is_local_authority():
		var dir = Vector3.ZERO
		if Input.is_action_pressed("move_forward"): dir += animated_skel.global_transform.basis.z
		if Input.is_action_pressed("move_left"): dir += animated_skel.global_transform.basis.x
		if Input.is_action_pressed("move_right"): dir -= animated_skel.global_transform.basis.x
		if Input.is_action_pressed("move_backward"): dir -= animated_skel.global_transform.basis.z
		
		var is_sprinting = Input.is_key_pressed(KEY_SHIFT)
		var jump_pressed = Input.is_action_just_pressed("jump")
		
		var arm_l = Input.is_action_pressed("grab_left")
		var arm_r = Input.is_action_pressed("grab_right")
		
		# FIXES THE SELF-RPC LOOP ERROR:
		if multiplayer.is_server():
			# If you are the host, process inputs directly on your server thread
			transmit_inputs(dir.normalized(), is_sprinting, jump_pressed, arm_l, arm_r)
		else:
			# If you are a client joining over Steam, send them up to the server normally
			transmit_inputs.rpc_id(1, dir.normalized(), is_sprinting, jump_pressed, arm_l, arm_r)
			
		animated_skel.rotation.y = camera_pivot.rotation.y

	# 2. SERVER FORCE CALCULATION
	if multiplayer.is_server():
		# DIVE FRICTION FIX: Dynamically raise body damping/friction when sliding on your stomach
		if is_diving:
			physical_bone_body.linear_velocity *= Vector3(0.85, 1.0, 0.85) # Increased damping from 0.9 to 0.85 to break ice sliding
		
		if not ragdoll_mode:
			var current_speed = SPEED
			if network_sprint:
				current_speed *= sprint_speed_multiplier
			
			walking = network_dir.length() > 0.1
			physical_bone_body.linear_velocity += network_dir * current_speed * delta 
			
			# Apply default structural damping only if not actively diving
			if not is_diving:
				physical_bone_body.linear_velocity *= Vector3(DAMPING, 1.0, DAMPING)
			
			# Floor check
			is_on_floor = false
			if on_floor_left.is_colliding() or on_floor_right.is_colliding():
				is_on_floor = true
					
			check_impact_knockout()
			
			if network_jump_pressed and is_on_floor and can_jump:
				if network_sprint:
					var launch_vector = (network_dir * dive_force) + (Vector3.UP * dive_upward_bias)
					if network_dir.length() <= 0.1:
						launch_vector = (animated_skel.global_transform.basis.z * dive_force) + (Vector3.UP * dive_upward_bias)
					physical_bone_body.linear_velocity = launch_vector
					is_diving = true
					jump_timer.start()
					can_jump = false
					_server_reset_dive_delayed()
				else:
					physical_bone_body.linear_velocity.y += JUMP_STRENGTH
					jump_timer.start()
					can_jump = false
					
			network_jump_pressed = false # Clear jump flag so it never chains into a wake-up frame
			
		if walking: animation_tree.set("parameters/walking/blend_amount",1)
		else: animation_tree.set("parameters/walking/blend_amount",0)
		
		# --- NEW: SEND BONE POSITIONS TO THE PUPPET CLIENTS ---
		var poses = []
		for i in physical_skel.get_bone_count():
			poses.append(physical_skel.get_bone_global_pose(i))
		
		# Broadcast the root body transform and all bone rotations unreliably (fastest for physics)
		rpc_sync_bones.rpc(poses, physical_bone_body.global_transform)

# --- NETWORK RPC HANDLERS ---

@rpc("any_peer", "unreliable")
func transmit_inputs(dir: Vector3, sprint: bool, jump: bool, arm_l: bool, arm_r: bool):
	if multiplayer.is_server():
		network_dir = dir
		network_sprint = sprint
		if jump: network_jump_pressed = true
		
		# Process grab transitions directly on server authoritative instances
		if active_arm_left and not arm_l: server_execute_throw(true)
		if active_arm_right and not arm_r: server_execute_throw(false)
			
		active_arm_left = arm_l
		active_arm_right = arm_r

@rpc("any_peer", "reliable")
func request_wakeup():
	if multiplayer.is_server():
		# Hard reset jump inputs on the server thread so it can never trigger a jump force application
		network_jump_pressed = false 
		
		if ragdoll_mode:
			ragdoll_mode = false
			knockout_timer = 0.0
			is_diving = false # Reset dive tracking completely upon waking up

@rpc("any_peer", "reliable")
func request_ragdoll_toggle():
	if multiplayer.is_server():
		if ragdoll_mode:
			ragdoll_mode = false
			knockout_timer = 0.0
		else:
			trigger_knockout()

func _server_reset_dive_delayed():
	await get_tree().create_timer(0.7).timeout
	is_diving = false

func server_execute_throw(is_left: bool):
	if is_left and grabbing_arm_left:
		if grabbed_object and grabbed_object is RigidBody3D:
			var raw_arm_swing = physical_bone_l_arm_2.angular_velocity.length()
			var calculated_swing_bonus = sqrt(raw_arm_swing) * swing_throw_multiplier
			var throw_dir = -animated_skel.global_transform.basis.z.normalized()
			var total_throw_force = clamp(5.0 + calculated_swing_bonus, 2.0, 35.0) 
			grabbed_object.apply_central_impulse(throw_dir * total_throw_force)
		grabbing_arm_left = false
		grabbed_object = null
		grab_joint_left.node_a = NodePath()
		grab_joint_left.node_b = NodePath()
	elif not is_left and grabbing_arm_right:
		if not grab_joint_right.node_b.is_empty():
			var obj = get_node_or_null(grab_joint_right.node_b)
			if obj and obj is RigidBody3D:
				var raw_arm_swing = physical_bone_r_arm_2.angular_velocity.length()
				var calculated_swing_bonus = sqrt(raw_arm_swing) * swing_throw_multiplier
				var throw_dir = -animated_skel.global_transform.basis.z.normalized()
				var total_throw_force = clamp(5.0 + calculated_swing_bonus, 2.0, 35.0) 
				obj.apply_central_impulse(throw_dir * total_throw_force)
		grabbing_arm_right = false
		grab_joint_right.node_a = NodePath()
		grab_joint_right.node_b = NodePath()

# spring related function
func hookes_law(displacement: Vector3, current_velocity: Vector3, stiffness: float, damping: float) -> Vector3:
	return (stiffness * displacement) - (damping * current_velocity)

func _on_r_grab_area_body_entered(body:Node3D):
	# check if the arm is touching something for grabbing
	if body is PhysicsBody3D and body.get_parent() != physical_skel:
		if active_arm_right and not grabbing_arm_right:
			grabbing_arm_right = true
			grab_joint_right.global_position = r_grab_area.global_position
			grab_joint_right.node_a = physical_bone_r_arm_2.get_path()
			grab_joint_right.node_b = body.get_path()

func _on_l_grab_area_body_entered(body:Node3D):
	# check if the arm is touching something for grabbing
	if body is PhysicsBody3D and body.get_parent() != physical_skel:
		if active_arm_left and not grabbing_arm_left:
			grabbing_arm_left = true
			grabbed_object = body
			grab_joint_left.global_position = l_grab_area.global_position
			grab_joint_left.node_a = physical_bone_l_arm_2.get_path()
			grab_joint_left.node_b = body.get_path()

func _on_jump_timer_timeout():
	# jump timer to avoid spamming jump and then fly away
	can_jump = true

func _on_skeleton_3d_skeleton_updated() -> void:
	if not ragdoll_mode:# if not in ragdoll mode
		# rotate the physical bones toward the animated bones rotations using hookes law
		for b:PhysicalBone3D in physics_bones:
			if not active_arm_left and b.name.contains("LArm"): continue # only rotated the arms if its activated
			if not active_arm_right and b.name.contains("RArm"): continue # only rotated the arms if its activated
			var target_transform: Transform3D = animated_skel.global_transform * animated_skel.get_bone_global_pose(b.get_bone_id())
			var current_transform: Transform3D = physical_skel.global_transform * physical_skel.get_bone_global_pose(b.get_bone_id())
			var rotation_difference: Basis = (target_transform.basis * current_transform.basis.inverse())
			var torque = hookes_law(rotation_difference.get_euler(), b.angular_velocity, angular_spring_stiffness, angular_spring_damping)
			torque = torque.limit_length(max_angular_force)
			
			# If diving, weaken structural core matching by 80% so limbs trail through the air fluidly
			if is_diving:
				torque *= 0.2
				
			b.angular_velocity += torque * current_delta

# --- CLIENT PUPPET SYNC ---
@rpc("authority", "unreliable", "call_remote")
func rpc_sync_bones(poses: Array, root_transform: Transform3D):
	# We only execute this on the client screens
	if not multiplayer.is_server():
		# 1. Sync the physical root so your camera tracking stays attached to the body
		physical_bone_body.global_transform = root_transform
		
		# 2. Force the client's visual skeleton to perfectly match the server's physical skeleton
		for i in poses.size():
			if i < physical_skel.get_bone_count():
				# Override the visual bones. The true parameter tells Godot it's an absolute global space override.
				physical_skel.set_bone_global_pose_override(i, poses[i], 1.0, true)

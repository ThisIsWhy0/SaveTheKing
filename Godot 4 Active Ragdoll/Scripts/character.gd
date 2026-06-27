extends Node3D

# movement/walking/jumping stuff
const JUMP_STRENGTH = 70
const SPEED = 50
@export var sprint_speed_multiplier: float = 1.75 # Customizable multiplier for sprinting
const DAMPING = 0.9
@onready var on_floor_left = $"Physical/Armature/Skeleton3D/Physical Bone LLeg2/OnFloorLeft" # shapecast on the feet to check if its on floor
@onready var on_floor_right = $"Physical/Armature/Skeleton3D/Physical Bone RLeg2/OnFloorRight" # shapecast on the feet to check if its on floor
@onready var jump_timer = $Physical/JumpTimer # timer to stop accidental double jump
var can_jump = true
var is_on_floor = false
var walking = false # if it is walking

# New missing physics mechanics parameters
@export var impact_threshold: float = 22.0     # Speed required to knock yourself out
@export var dive_force: float = 65.0          # Forward velocity push for diving
@export var dive_upward_bias: float = 15.0    # Vertical launch for diving
@export var base_throw_power: float = 40.0     # Power multiplier for throwing objects
@export var max_fall_time_before_ragdoll: float = 1.5 # How long to be airborne before turning into a ragdoll

var knockout_timer: float = 0.0
var air_timer: float = 0.0                     # Tracks how long player has been falling
var is_diving: bool = false

# spring stuff
@export var angular_spring_stiffness: float = 4000.0
@export var angular_spring_damping: float = 80.0
@export var max_angular_force: float = 9999.0

var physics_bones = [] # all physical bones

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

func check_impact_knockout():
	# If we hit the ground or a wall harder than our threshold while not already unconscious
	if not ragdoll_mode and physical_bone_body.linear_velocity.length() > impact_threshold:
		# Check if the floor shapecasts are colliding during high speed to confirm a crash down
		if on_floor_left.is_colliding() or on_floor_right.is_colliding():
			trigger_knockout()

func trigger_knockout():
	ragdoll_mode = true
	knockout_timer = 2.0 # Keep player down as a ragdoll for 2 seconds
	
	# Sever active grabbing joints instantly upon getting knocked out
	grabbing_arm_left = false
	grab_joint_left.node_a = NodePath()
	grab_joint_left.node_b = NodePath()
	grabbing_arm_right = false
	grab_joint_right.node_a = NodePath()
	grab_joint_right.node_b = NodePath()

func _ready():
	physical_skel.physical_bones_start_simulation()# activate ragdoll
	physics_bones = physical_skel.get_children().filter(func(x): return x is PhysicalBone3D) # get all the physical bones

func _input(event):
	# If the player is in a ragdoll state, pressing jump instantly recovers them
	if ragdoll_mode and Input.is_action_just_pressed("jump"):
		ragdoll_mode = false
		knockout_timer = 0.0
		air_timer = 0.0
		return

	if Input.is_action_just_pressed("ragdoll"):
		ragdoll_mode = bool(1-int(ragdoll_mode))

	active_arm_left = Input.is_action_pressed("grab_left")
	active_arm_right = Input.is_action_pressed("grab_right")
	
	# Release and THROW left arm object
	if (not active_arm_left and grabbing_arm_left) or ragdoll_mode:
		if grabbed_object and grabbed_object is RigidBody3D:
			# Calculate throw direction based on camera forward vector
			var throw_dir = -camera_pivot.global_transform.basis.z.normalized()
			# Combine throw base power and character's moving forward velocity vector
			var body_forward_speed = physical_bone_body.linear_velocity.dot(throw_dir)
			var final_impulse = throw_dir * (base_throw_power + max(0.0, body_forward_speed))
			
			grabbed_object.apply_central_impulse(final_impulse)
			
		grabbing_arm_left = false
		grabbed_object = null
		grab_joint_left.node_a = NodePath()
		grab_joint_left.node_b = NodePath()
		
	# Release and THROW right arm object
	if (not active_arm_right and grabbing_arm_right) or ragdoll_mode:
		# Locate node_b directly from joint setup
		if not grab_joint_right.node_b.is_empty():
			var obj = get_node_or_null(grab_joint_right.node_b)
			if obj and obj is RigidBody3D:
				var throw_dir = -camera_pivot.global_transform.basis.z.normalized()
				var body_forward_speed = physical_bone_body.linear_velocity.dot(throw_dir)
				var final_impulse = throw_dir * (base_throw_power + max(0.0, body_forward_speed))
				
				obj.apply_central_impulse(final_impulse)
				
		grabbing_arm_right = false
		grab_joint_right.node_a = NodePath()
		grab_joint_right.node_b = NodePath()

func _process(delta):
	# Wake up system for knockouts (via natural timer decay)
	if ragdoll_mode and knockout_timer > 0.0:
		knockout_timer -= delta
		# If timer runs out and the body has mostly stopped rolling/moving
		if knockout_timer <= 0.0 and physical_bone_body.linear_velocity.length() < 1.5:
			ragdoll_mode = false # Return control back to active ragdoll state
	
	var r = clamp((camera_pivot.rotation.x*2)/(PI)*2.1,-1,1)
	if active_arm_left or active_arm_right:
		animation_tree.set("parameters/grab_dir/blend_position",r)
	else:
		animation_tree.set("parameters/grab_dir/blend_position",0)

func _physics_process(delta):
	current_delta = delta
	if not ragdoll_mode:# if not in ragdoll mode
		
		# check if shift modifier is active
		var is_sprinting = Input.is_key_pressed(KEY_SHIFT)
		var current_speed = SPEED
		if is_sprinting:
			current_speed *= sprint_speed_multiplier
		
		# walking control
		walking = false
		var dir = Vector3.ZERO
		if Input.is_action_pressed("move_forward"):
			dir += animated_skel.global_transform.basis.z
			walking = true
		if Input.is_action_pressed("move_left"):
			dir += animated_skel.global_transform.basis.x
			walking = true
		if Input.is_action_pressed("move_right"):
			dir -= animated_skel.global_transform.basis.x
			walking = true
		if Input.is_action_pressed("move_backward"):
			dir -= animated_skel.global_transform.basis.z
			walking = true
		dir = dir.normalized()

		physical_bone_body.linear_velocity += dir * current_speed * delta #move character
		physical_bone_body.linear_velocity *= Vector3(DAMPING,1,DAMPING)# add damping to make it less slippery
		
		#check if is on floor
		is_on_floor = false
		if on_floor_left.is_colliding():
			for i in on_floor_left.get_collision_count():
				if on_floor_left.get_collision_normal(i).y > 0.5:
					is_on_floor = true
					break
		if not is_on_floor: 
			if on_floor_right.is_colliding():
				for i in on_floor_right.get_collision_count():
					if on_floor_right.get_collision_normal(i).y > 0.5:
						is_on_floor = true
						break
		
		# Track structural time spent falling through free air
		if not is_on_floor:
			air_timer += delta
			if air_timer >= max_fall_time_before_ragdoll:
				trigger_knockout()
		else:
			air_timer = 0.0
				
		# Put this here right below floor calculation process:
		check_impact_knockout()
		
		# Jump / Dive Input Handling Logic
		if Input.is_action_just_pressed("jump") and is_on_floor and can_jump:
			if is_sprinting:
				# 1. DIVING: Only triggers if actively holding down shift modifier
				var movement_dir = Vector3.ZERO
				if Input.is_action_pressed("move_forward"): movement_dir += animated_skel.global_transform.basis.z
				if Input.is_action_pressed("move_left"): movement_dir += animated_skel.global_transform.basis.x
				if Input.is_action_pressed("move_right"): movement_dir -= animated_skel.global_transform.basis.x
				if Input.is_action_pressed("move_backward"): movement_dir -= animated_skel.global_transform.basis.z
				
				# Fallback to camera facing direction if diving while dead-still
				if movement_dir.length() <= 0.1:
					movement_dir = animated_skel.global_transform.basis.z
					
				movement_dir = movement_dir.normalized()
				var launch_vector = (movement_dir * dive_force) + (Vector3.UP * dive_upward_bias)
				physical_bone_body.linear_velocity = launch_vector
				
				is_diving = true
				jump_timer.start()
				can_jump = false
				
				await get_tree().create_timer(0.7).timeout
				is_diving = false
			else:
				# 2. NORMAL JUMP: Triggers if shift modifier is unpressed
				physical_bone_body.linear_velocity.y += JUMP_STRENGTH
				jump_timer.start()
				can_jump = false
		
		#play walking animation/idle
		if walking:animation_tree.set("parameters/walking/blend_amount",1)
		else:animation_tree.set("parameters/walking/blend_amount",0)

		#rotate the character toward the camera direction
		animated_skel.rotation.y = camera_pivot.rotation.y

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

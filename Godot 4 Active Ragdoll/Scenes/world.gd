extends Node3D

@export var player_character_scene: PackedScene = preload("res://Scenes/character.tscn")

func _ready() -> void:
	print("[WORLD] Scene loaded. Initializing Multiplayer Spawner...")
	
	# 1. Direct path allocation
	$MultiplayerSpawner.spawn_path = get_path()
	
	# 2. Wait until the end of the frame layout pass so the scene tree is completely stable
	await get_tree().process_frame
	
	# 3. Explicit server verification
	if multiplayer.has_multiplayer_peer():
		print("[WORLD] Network status: Connected. Connection Status: ", multiplayer.multiplayer_peer.get_connection_status())
		
		if multiplayer.is_server():
			print("[WORLD] Authority recognized: SERVER/HOST. Hooking disconnection pipelines...")
			multiplayer.peer_disconnected.connect(_despawn_network_player)
			
			# Fallback ID safety: If the peer unique ID is unready, force host ID 1
			var host_id = multiplayer.get_unique_id()
			if host_id == 0:
				host_id = 1
				
			_spawn_network_player(host_id)
		else:
			print("[WORLD] Authority recognized: CLIENT. Waiting for server replication...")
	else:
		print("[WORLD] ERROR: No active multiplayer peer found! Did SteamManager fail to bind?")

func _spawn_network_player(id: int) -> void:
	print("[WORLD] Attempting to instantiate character node for Peer ID: ", id)
	
	if player_character_scene == null:
		print("[WORLD] ERROR: player_character_scene is null!")
		return
		
	var new_player = player_character_scene.instantiate()
	new_player.name = str(id)
	new_player.player_id = id
	
	# 1. First, attach the node into the scene tree so it exists spatially
	add_child(new_player, true) 
	
	# 2. Position it securely in free air well clear of any floor mesh bounding boxes
	new_player.global_position = Vector3(0, 5, 0)
	
	# 3. Call a deferred function to wake up the ragdoll simulation after placement frames settle
	if new_player.has_method("safely_activate_physics"):
		new_player.call_deferred("safely_activate_physics")
		
	print("[WORLD] SUCCESS: Character node safely spawned above map geometry: ", new_player.get_path())

func _despawn_network_player(id: int) -> void:
	var target_avatar = get_node_or_null(str(id))
	if target_avatar:
		print("[WORLD] Removing disconnected peer avatar node: ", id)
		target_avatar.queue_free()

extends Node3D

@export var player_character_scene: PackedScene = preload("res://Scenes/character.tscn")

func _ready() -> void:
	print("[WORLD] Setting up Multiplayer Spawner...")
	$MultiplayerSpawner.spawn_path = NodePath()
	
	if multiplayer.is_server():
		print("[WORLD] Host recognized. Initializing server spawn connections...")
		
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(rpc_despawn_network_player)
		
		rpc_spawn_network_player.rpc(multiplayer.get_unique_id())
	else:
		print("[WORLD] Client recognized. Standing by for server replication...")

func _on_peer_connected(id: int) -> void:
	if has_node(str(id)):
		print("[WORLD] Warning: Peer ", id, " already has an active character. Skipping spawn.")
		return
		
	print("[WORLD] Late client connected over Steam. Initializing spawn for Peer: ", id)
	rpc_spawn_network_player.rpc(id)
	
	for child in get_children():
		var child_name := child.name as String
		if child_name.is_valid_int():
			var peer_id := int(child_name)
			if peer_id != id:
				rpc_spawn_network_player.rpc_id(id, peer_id)

@rpc("authority", "call_local", "reliable")
func rpc_spawn_network_player(id: int) -> void:
	if has_node(str(id)):
		return
	
	if id == 0: id = 1
	
	print("[WORLD] Spawning character node for ID: ", id)
	var new_player = player_character_scene.instantiate()
	
	new_player.name = str(id)
	new_player.player_id = id
	
	new_player.position = Vector3(0, 5, 0)
	
	add_child(new_player, true)

@rpc("authority", "call_local", "reliable")
func rpc_despawn_network_player(id: int) -> void:
	var target_avatar = get_node_or_null(str(id))
	if target_avatar:
		print("[WORLD] Removing disconnected peer node tree: ", id)
		target_avatar.queue_free()

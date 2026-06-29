extends Node3D

@export var player_character_scene: PackedScene = preload("res://Scenes/character.tscn")

func _ready() -> void:
	print("[WORLD] Setting up Multiplayer Spawner...")
	$MultiplayerSpawner.spawn_path = get_path()
	
	# Only the Server/Host needs to set up spawning logic.
	# Clients will simply bypass this block and wait for the server to send them a body.
	if multiplayer.is_server():
		print("[WORLD] Host recognized. Initializing server spawn connections...")
		
		# Hook network events to handle incoming players dynamically
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_despawn_network_player)
		
		# Instantly spawn the host avatar right now (Peer ID 1)
		_spawn_network_player(multiplayer.get_unique_id())
	else:
		print("[WORLD] Client recognized. Standing by for server replication...")

func _on_peer_connected(id: int) -> void:
	if has_node(str(id)):
		print("[WORLD] Warning: Peer ", id, " already has an active character. Skipping spawn.")
		return
		
	print("[WORLD] Late client connected over Steam. Initializing spawn for Peer: ", id)
	_spawn_network_player(id)

func _spawn_network_player(id: int) -> void:
	if id == 0: id = 1
	
	print("[WORLD] Spawning character node for ID: ", id)
	var new_player = player_character_scene.instantiate()
	
	# Name the node so `is_local_authority()` works perfectly for inputs!
	new_player.name = str(id)
	new_player.player_id = id 
	
	# Set local position safely out of the floor
	new_player.position = Vector3(0, 5, 0)
	
	# Add it to the tree. The Server retains ownership of the Synchronizer automatically.
	add_child(new_player, true)

func _despawn_network_player(id: int) -> void:
	var target_avatar = get_node_or_null(str(id))
	if target_avatar:
		print("[WORLD] Removing disconnected peer node tree: ", id)
		target_avatar.queue_free()

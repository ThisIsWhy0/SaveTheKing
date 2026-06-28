extends Node3D

@export var player_character_scene: PackedScene = preload("res://Scenes/character.tscn")

func _ready() -> void:
	$MultiplayerSpawner.spawn_path = get_path()
	
	if multiplayer.is_server():
		# Remove multiplayer.peer_connected hook from here! 
		# The MultiplayerSpawner takes care of syncing new peers automatically.
		multiplayer.peer_disconnected.connect(_despawn_network_player)
		
		# Spawn exactly one authoritative player avatar for the host instance
		_spawn_network_player(multiplayer.get_unique_id())

func _spawn_network_player(id: int) -> void:
	print("Spawning primary player instance for Steam ID/Peer: ", id)
	var new_player = player_character_scene.instantiate()
	new_player.name = str(id)
	new_player.player_id = id
	
	# Lift the spawn point slightly up along the Y axis (e.g. Vector3(0, 5, 0)) 
	# to prevent physics bones from clipping into floor geometry on initialization frame
	new_player.global_position = Vector3(0, 5, 0)
	
	add_child(new_player, true) 

func _despawn_network_player(id: int) -> void:
	var target_avatar = get_node_or_null(str(id))
	if target_avatar:
		target_avatar.queue_free()

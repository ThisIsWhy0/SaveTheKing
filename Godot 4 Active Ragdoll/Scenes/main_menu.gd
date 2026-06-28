extends Control

func _ready() -> void:
	$HostButton.pressed.connect(_on_host_pressed)
	$FindButton.pressed.connect(_on_find_pressed)
	SteamManager.lobbies_found.connect(_on_steam_lobbies_found)

func _on_host_pressed() -> void:
	SteamManager.create_lobby()

func _on_find_pressed() -> void:
	SteamManager.search_for_lobbies()

func _on_steam_lobbies_found(lobby_list: Array) -> void:
	if lobby_list.size() == 0:
		print("No active lobbies found nearby.")
		return
		
	# For prototyping, instantly join the first available lobby found
	print("Lobby found! Connecting to: ", lobby_list[0]["name"])
	SteamManager.join_lobby(lobby_list[0]["id"])

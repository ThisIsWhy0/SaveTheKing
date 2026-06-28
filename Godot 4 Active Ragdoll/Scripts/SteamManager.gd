extends Node

var is_steam_running: bool = false
var lobby_id: int = 0
var network_peer: SteamMultiplayerPeer = SteamMultiplayerPeer.new()

# Signal to notify your UI when lobbies are found
signal lobbies_found(lobby_list: Array)

func _ready() -> void:
	_initialize_steam()

func _initialize_steam() -> void:
	# Use steamInitEx() to safely pull the verbose Dictionary response
	# No arguments are needed if your steam_appid.txt is present in the root folder
	var init_response: Dictionary = Steam.steamInitEx()
	
	# In modern GodotSteam, a status code of 0 means "Successfully initialized"
	if init_response["status"] == 0:
		is_steam_running = true
		print("Steam initialized successfully. Player Name: ", Steam.getPersonaName())
		
		# Connect Steam signaling callbacks
		Steam.lobby_created.connect(_on_lobby_created)
		Steam.lobby_match_list.connect(_on_lobby_match_list)
		Steam.lobby_joined.connect(_on_lobby_joined)
	else:
		print("Steam failed to initialize: ", init_response["verbal"])

func _process(_delta: float) -> void:
	if is_steam_running:
		Steam.run_callbacks()

# --- LOBBY COMMANDS ---

func create_lobby() -> void:
	if is_steam_running:
		print("Creating a public Steam lobby...")
		Steam.createLobby(Steam.LOBBY_TYPE_PUBLIC, 6) # Max 6 players for party game chaos

func _on_lobby_created(connect_status: int, created_lobby_id: int) -> void:
	if connect_status == 1:
		lobby_id = created_lobby_id
		print("Lobby created successfully. ID: ", lobby_id)
		
		# Set lobby data so others can filter it in searches
		Steam.setLobbyData(lobby_id, "game_type", "savetheking_ragdoll")
		Steam.setLobbyData(lobby_id, "name", Steam.getPersonaName() + "'s Lobby")
		
		# Flush out old states with a fresh peer instance
		network_peer = SteamMultiplayerPeer.new()
		
		# --- CHANGE THIS FROM lobby_id TO 0 ---
		var socket_created = network_peer.create_host(0) 
		
		if socket_created == OK:
			multiplayer.multiplayer_peer = network_peer
			print("Multiplayer host assigned successfully via Steam sockets.")
			
			# Load the game world scene immediately for the host
			get_tree().change_scene_to_file("res://Scenes/world.tscn")
		else:
			print("Failed to bind Steam host socket! Error code: ", socket_created)

func search_for_lobbies() -> void:
	if is_steam_running:
		print("Searching for matching game lobbies...")
		Steam.addRequestLobbyListDistanceFilter(Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE)
		Steam.addRequestLobbyListStringFilter("game_type", "savetheking_ragdoll", Steam.LOBBY_COMPARISON_EQUAL)
		Steam.requestLobbyList()

func _on_lobby_match_list(lobbies: Array) -> void:
	var lobby_list_data = []
	for current_lobby in lobbies:
		var lobby_name = Steam.getLobbyData(current_lobby, "name")
		lobby_list_data.append({"id": current_lobby, "name": lobby_name})
	
	lobbies_found.emit(lobby_list_data)

func join_lobby(target_lobby_id: int) -> void:
	if is_steam_running:
		print("Joining Steam lobby...")
		Steam.joinLobby(target_lobby_id)

func _on_lobby_joined(joined_lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	if response == 1: # ChatRoomConnectStateSuccess
		lobby_id = joined_lobby_id
		
		# --- THE CRITICAL FIX ---
		# Get the Steam ID of the person who owns/hosted this lobby
		var lobby_owner = Steam.getLobbyOwner(lobby_id)
		# Get our own unique Steam ID
		var my_steam_id = Steam.getSteamID()
		
		# If WE are the owner, we already initialized the host peer inside _on_lobby_created!
		# Bypassing this stops the host from downgrading itself into a client.
		if lobby_owner == my_steam_id:
			print("[STEAM] We created this lobby. Skipping client pipe initialization.")
			return
			
		print("Successfully joined a friend's Steam lobby backend. ID: ", lobby_id)
		
		# Cleanly disconnect the current multiplayer peer if it's lingering
		multiplayer.multiplayer_peer = null
		
		# Re-instantiate a clean peer instance to completely wipe out any hosting states
		network_peer = SteamMultiplayerPeer.new()
		
		# Create the client connection over the freshly allocated network pipe
		var client_created = network_peer.create_client(lobby_id, 0)
		
		if client_created == OK:
			multiplayer.multiplayer_peer = network_peer
			print("Multiplayer client pipe assigned successfully over Steam P2P.")
			
			# Load the game world stage for the joining client player
			get_tree().change_scene_to_file("res://Scenes/world.tscn")
		else:
			print("Failed to initialize Steam client socket connection! Error code: ", client_created)

extends Node2D

@export var highlight_tile: PackedScene  # Highlight tile packed scene for hover effect

# Preload the unit scenes
@export var unit_soldier: PackedScene  # Set the unit scene in the Inspector
@export var unit_merc: PackedScene  # Set the unit scene in the Inspector
@export var unit_dog: PackedScene  # Set the unit scene in the Inspector

@export var unit_zombie: PackedScene  # Set the unit scene for the zombie in the Inspector
@export var unit_radioactive_zombie: PackedScene  # Set the unit scene for the zombie in the Inspector
@export var unit_crusher_zombie: PackedScene  # Set the unit scene for the zombie in the Inspector

@export var M1: PackedScene  
@export var M2: PackedScene  
@export var R1: PackedScene  
@export var R3: PackedScene 
@export var S2: PackedScene  
@export var S3: PackedScene  

@onready var tilemap = get_parent().get_node("TileMap")  # Reference to the TileMap
@onready var map_manager = get_node("/root/MapManager")

# Tile IDs for non-spawnable tiles
var WATER # Replace with the actual tile ID for water

# Track the number of player units spawned
var player_units_spawned = 0
var can_spawn = true  # Flag to control if further spawning is allowed

# Track unique zombie IDs
var zombie_id_counter = 0  # Counter to assign unique IDs to zombies

var zombie_names = [
	"Walker", "Crawler", "Stalker", "Biter",
	"Lurker", "Rotter", "Shambler", "Moaner",
	"Sniffer", "Stumbler", "Gnawer", "Howler",
	"Groaner", "Clawer", "Grunter", "Chomper",
	"Slasher", "Growler", "Drooler", "Scratcher",
	"Bleeder", "Rumbler", "Sludger", "Mangler",
	"Spitter", "Hunter", "Dragger", "Slimer",
	"Ripper", "Rager", "Slasher", "Tumbler"
]

signal units_spawned

func _ready():
	# Wait for a few frames to ensure the TileMap has generated fully
	await get_tree().process_frame  # Waits for one frame
	await get_tree().process_frame  # Additional frames if needed

	# Shuffle the zombie names to randomize the order
	zombie_names.shuffle()
	
	if map_manager.map_1:
		WATER = 0
	elif map_manager.map_2:
		WATER = 9
	elif map_manager.map_3:
		WATER = 15
	elif map_manager.map_4:
		WATER = 21
	else:
		print("Error: No map selected, defaulting WATER to 0.")
		WATER = 0  # Fallback value if no map is selected
			
	# Now check if the TileMap has usable tiles before proceeding
	if tilemap.get_used_rect().size.x == 0 or tilemap.get_used_rect().size.y == 0:
		print("Error: TileMap still has no usable tiles after waiting.")
	else:		
		spawn_player_units()  # Proceed to spawn units if the map has tiles

func spawn_player_units():
	# List of unit scenes for easier access
	var units = [unit_soldier, unit_merc, unit_dog, M1, M2, R1, R3, S2, S3]

	# Divide the map into 9 zones
	var zones = initialize_zones()
	if zones.is_empty():
		print("Error: Could not initialize zones for spawning.")
		return

	# Randomly select one zone for players
	var player_zone = zones.pop_at(randi() % zones.size())

	# Spawn player units in the selected zone
	var max_spawn_attempts_per_unit = 1024
	var spawned_units = 0

	for unit_type in units:
		var attempts = 0
		while attempts < max_spawn_attempts_per_unit:
			var spawn_position = get_random_tile_in_zone(player_zone)
			if spawn_position != Vector2i(-1, -1):  # Valid position found
				var unit_instance = spawn_unit_at(unit_type, spawn_position)
				if unit_instance != null:
					player_units_spawned += 1
					spawned_units += 1
					break
			attempts += 1

		if attempts >= max_spawn_attempts_per_unit:
			print("Failed to spawn unit after multiple attempts:", unit_type)

	if spawned_units < units.size():
		print("Warning: Not all player units were spawned. Spawned:", spawned_units, "Expected:", units.size())

	# Spawn zombies in the remaining zones
	await spawn_zombies(zones)
	notify_units_spawned()

func spawn_zombies(zombie_zones: Array):
	var zombie_count = min(map_manager.grid_width, map_manager.grid_height)
	var zombie_count_per_zone = zombie_count / zombie_zones.size()
	zombie_names.shuffle()  # Shuffle zombie names

	for zone in zombie_zones:
		var spawn_attempts = 0
		while spawn_attempts < zombie_count_per_zone:
			var spawn_position = get_random_tile_in_zone(zone)
			if spawn_position != Vector2i(-1, -1):
				var zombie_instance = create_zombie_instance()
				zombie_instance.position = tilemap.map_to_local(spawn_position)
				zombie_instance.z_index = int(zombie_instance.position.y)

				# Assign unique ID and name
				zombie_instance.set("zombie_id", zombie_id_counter)
				zombie_id_counter += 1
				if zombie_names.size() > 0:
					zombie_instance.zombie_name = zombie_instance.zombie_type + " " + zombie_names.pop_back()

				# Add to scene tree and group
				add_child(zombie_instance)
				zombie_instance.add_to_group("zombies")
				spawn_attempts += 1

	print("All zombies have been spawned.")

# Divide the map into 9 zones
func initialize_zones() -> Array:
	var map_size = tilemap.get_used_rect().size

	if map_size.x == 0 or map_size.y == 0:
		print("Error: TileMap has no usable tiles.")
		return []

	var zones = []
	var zone_width = map_size.x / 3
	var zone_height = map_size.y / 3

	for i in range(3):
		for j in range(3):
			zones.append(Rect2(
				Vector2i(i * zone_width, j * zone_height),
				Vector2i(zone_width, zone_height)
			))

	return zones

# Get a random tile in a specific zone
func get_random_tile_in_zone(zone: Rect2) -> Vector2i:
	var attempts = 0
	var max_attempts = 1024
	while attempts < max_attempts:
		var random_x = randi_range(zone.position.x, zone.position.x + zone.size.x - 1)
		var random_y = randi_range(zone.position.y, zone.position.y + zone.size.y - 1)
		var tile_pos = Vector2i(random_x, random_y)

		if is_spawnable_tile(tile_pos) and not is_occupied(tile_pos) and is_blank_tile(tile_pos):
			return tile_pos
		attempts += 1

	print("Could not find a valid spawn tile in zone:", zone)
	return Vector2i(-1, -1)

# Create a zombie instance based on map conditions
func create_zombie_instance() -> Node2D:
	if GlobalManager.current_map_index == 2:
		return unit_radioactive_zombie.instantiate() if randi() % 2 == 0 else unit_zombie.instantiate()
	elif GlobalManager.current_map_index == 3:
		var roll = randi() % 10
		if roll < 1:
			return unit_radioactive_zombie.instantiate()
		elif roll < 6:
			return unit_crusher_zombie.instantiate()
		else:
			return unit_zombie.instantiate()
	else:
		return unit_zombie.instantiate()

func spawn_unit_at(unit_type: PackedScene, tile_pos: Vector2i) -> Node2D:
	if unit_type == null:
		print("Unit scene not assigned.")
		return null

	# Instantiate and position the unit
	var unit_instance = unit_type.instantiate() as Node2D
	unit_instance.position = tilemap.map_to_local(tile_pos)
	unit_instance.z_index = int(unit_instance.position.y)

	# Randomly determine the direction (left or right)
	var random_direction = randi() % 2 == 0  # True for right, False for left
	unit_instance.scale = Vector2(
		abs(unit_instance.scale.x) if random_direction else -abs(unit_instance.scale.x),
		unit_instance.scale.y
	)

	# Add to scene tree and player units group
	add_child(unit_instance)
	unit_instance.add_to_group("player_units")
	print("Player unit spawned at:", tile_pos, "Facing:", "Right" if random_direction else "Left")

	return unit_instance

# Checks if a tile is spawnable (not water)
func is_spawnable_tile(tile_pos: Vector2i) -> bool:
	var tile_id = tilemap.get_cell_source_id(0, tile_pos)
	return tile_id != WATER

# Checks if a tile is spawnable (not water)
func is_blank_tile(tile_pos: Vector2i) -> bool:
	var tile_id = tilemap.get_cell_source_id(0, tile_pos)
	return tile_id != -1

# Checks if a tile is occupied by another unit or structure
func is_occupied(tile_pos: Vector2i) -> bool:
	# Check if any units or structures occupy this tile
	for unit in get_tree().get_nodes_in_group("player_units"):
		if tilemap.local_to_map(unit.position) == tile_pos:
			return true
	for zombie in get_tree().get_nodes_in_group("zombies"):
		if tilemap.local_to_map(zombie.position) == tile_pos:
			return true			
	for structure in get_tree().get_nodes_in_group("structures"):
		if tilemap.local_to_map(structure.position) == tile_pos:
			return true
	return false

func notify_units_spawned():
	emit_signal("units_spawned")

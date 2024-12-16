extends Node2D

# Configuration variables
var max_targets = 7 # Maximum number of zombies to attack
var attack_damage = 50 # Damage dealt per attack
var fade_duration = 0.5 # Duration for fade out and in
var cooldown = 3.0 # Cooldown for the ability

var targeted_zombies = [] # List of zombies to attack
var attack_index = 0 # Tracks which zombie is currently being attacked
var is_shadow_step_active = false

@export var hover_tile_path: NodePath = "/root/MapManager/HoverTile"
@onready var hover_tile = get_node_or_null(hover_tile_path)

var WATER_TILE_ID = 0
@onready var map_manager = get_parent().get_node("/root/MapManager")

var attacked_zombies = []  # List to track already attacked zombies

func _process(delta: float) -> void:
	if map_manager.map_1:
		WATER_TILE_ID = 0
	elif map_manager.map_2:
		WATER_TILE_ID = 9
	elif map_manager.map_3:
		WATER_TILE_ID = 15
	elif map_manager.map_4:
		WATER_TILE_ID = 21
	else:
		print("Error: No map selected, defaulting WATER to 0.")
		WATER_TILE_ID = 0  # Fallback value if no map is selected	

func _input(event):
	# Check for mouse click
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# Block gameplay input if the mouse is over GUI
		if is_mouse_over_gui():
			print("Input blocked by GUI.")
			return  # Prevent further input handling

		# Reference the TileMap node
		var tilemap: TileMap = get_node("/root/MapManager/TileMap")

		# Get the boundaries of the map's used rectangle
		var map_size = tilemap.get_used_rect()  # Rect2: position and size of the used tiles
		var map_origin_x = map_size.position.x  # Starting x-coordinate of the used rectangle
		var map_origin_y = map_size.position.y  # Starting y-coordinate of the used rectangle
		var map_width = map_size.size.x         # Width of the map in tiles
		var map_height = map_size.size.y        # Height of the map in tiles

		var global_mouse_position = get_global_mouse_position() 
		global_mouse_position.y += 8
			
		# Convert the global mouse position to tile coordinates
		var mouse_local = tilemap.local_to_map(global_mouse_position)

		# Check if the mouse is outside the bounds of the used rectangle
		if mouse_local.x < map_origin_x or mouse_local.x >= map_origin_x + map_width or \
		   mouse_local.y < map_origin_y or mouse_local.y >= map_origin_y + map_height:
			return  # Exit the function if the mouse is outside the map
						
		# Ensure hover_tile exists and "Sarah Reese" is selected
		if hover_tile and hover_tile.selected_player and hover_tile.selected_player.player_name == "Chuck. Genius" and GlobalManager.shadows_toggle_active == true:
			var target_zombie = get_zombie_at_tile(mouse_local)
			if target_zombie:
				var hud_manager = get_parent().get_parent().get_parent().get_node("HUDManager")  # Adjust the path if necessary
				hud_manager.hide_special_buttons()								
				shadow_step(target_zombie)

func shadow_step(target_zombie):
	# Reset variables for this ability use
	targeted_zombies.clear()
	attack_index = 0
	is_shadow_step_active = true

	# Start with the clicked zombie
	targeted_zombies.append(target_zombie)

	# Find nearby zombies (excluding the clicked zombie)
	var nearby_zombies = find_nearest_zombies(max_targets - 1)
	targeted_zombies.append_array(nearby_zombies)

	if targeted_zombies.is_empty():
		print("No zombies found for Shadow Step.")
		is_shadow_step_active = false
		return

	await get_tree().create_timer(0.1).timeout
	# Start the attack sequence
	attack_next_zombie()
	
func find_nearest_zombies(max_count: int) -> Array:
	var zombies_in_range = []
	var zombies = get_tree().get_nodes_in_group("zombies")
	var current_position = get_parent().tile_pos

	# Manual bubble sort based on distance to `current_position`
	for i in range(zombies.size()):
		for j in range(0, zombies.size() - i - 1):
			var dist_a = current_position.distance_to(zombies[j].tile_pos)
			var dist_b = current_position.distance_to(zombies[j + 1].tile_pos)
			if dist_a > dist_b:
				# Swap the zombies
				var temp = zombies[j]
				zombies[j] = zombies[j + 1]
				zombies[j + 1] = temp

	# Collect the nearest zombies up to max_count
	for zombie in zombies:
		zombies_in_range.append(zombie)
		if zombies_in_range.size() >= max_count:
			break

	return zombies_in_range


func get_zombie_at_tile(tile_pos: Vector2i):
	var zombies = get_tree().get_nodes_in_group("zombies")
	for zombie in zombies:
		if zombie.tile_pos == tile_pos:
			return zombie
	return null

func attack_next_zombie():
	if attack_index >= targeted_zombies.size():
		print("Shadow Step sequence complete.")
		is_shadow_step_active = false  # Mark this unit's action as complete
		
		GlobalManager.shadows_toggle_active = false
		
		get_parent().has_attacked = true
		get_parent().has_moved = true	
		get_parent().check_end_turn_conditions()	
		return

	var target = targeted_zombies[attack_index]
	
	# Skip if the target is invalid or already attacked
	if not target or not target.is_inside_tree() or target in attacked_zombies:
		print("Target is no longer valid or already attacked. Skipping.")
		attack_index += 1
		attack_next_zombie()
		return

	# Fade out, teleport, fade in, and attack
	await fade_out(get_parent())
	teleport_to_adjacent_tile(target)
	await fade_in(get_parent())
	
	await get_tree().create_timer(0.2).timeout
	
	# Play SFX
	get_parent().get_child(9).stream = get_parent().slash_audio
	get_parent().get_child(9).play()
			
	perform_attack(target)
	
	# Mark this zombie as attacked
	attacked_zombies.append(target)
	attack_index += 1
	attack_next_zombie()

func perform_attack(target):
	if target and target.is_inside_tree():	
		# Flip to face the target
		update_facing_direction(target.global_position)

		# Play attack animation
		get_parent().get_child(0).play("attack")

		# Wait for the attack animation to finish before applying damage
		await get_tree().create_timer(0.5).timeout

		# Play SFX
		target.audio_player.stream = target.zombie_audio
		target.audio_player.play()
		
		# Apply damage to the target
		target.flash_damage()
		target.apply_damage(get_parent().attack_damage)

		print("Attacked zombie at tile:", target.tile_pos)

func update_facing_direction(target_pos: Vector2):
	var tilemap: TileMap = get_node("/root/MapManager/TileMap")

	# Convert the target position to map coordinates, then back to world coordinates
	var target_world_pos = target_pos

	# Calculate the direction to the target position
	var direction = (target_world_pos - get_parent().position).normalized()

	# Determine the direction of movement based on target and current position
	if direction.x > 0:
		get_parent().scale.x = -1  # Facing right (East)
	elif direction.x < 0:
		get_parent().scale.x = 1  # Facing left (West)
  
		
func teleport_to_adjacent_tile(target):
	var tilemap: TileMap = get_node("/root/MapManager/TileMap")
	var target_position = target.tile_pos

	# Find an adjacent tile
	var directions = [
		Vector2i(0, -1),
		Vector2i(0, 1),
		Vector2i(-1, 0),
		Vector2i(1, 0)
	]

	for direction in directions:
		var adjacent_tile = target_position + direction
		if is_tile_movable(adjacent_tile):
			var world_pos = tilemap.map_to_local(adjacent_tile)
			get_parent().position = world_pos
			return

	print("No valid adjacent tile found for teleportation.")

# Check if a tile is movable
func is_tile_movable(tile_pos: Vector2i) -> bool:
	var tilemap: TileMap = get_node("/root/MapManager/TileMap")
	var tile_id = tilemap.get_cell_source_id(0, tile_pos)
	if is_water_tile(tile_id):
		return false
	if is_structure(tile_pos) or is_unit_present(tile_pos) or !is_blank_tile(tile_pos):
		return false
	return true

# Checks if a tile is spawnable (not water)
func is_blank_tile(tile_pos: Vector2i) -> bool:
	var tilemap: TileMap = get_node("/root/MapManager/TileMap")
	var tile_id = tilemap.get_cell_source_id(0, tile_pos)
	return tile_id != -1

# Check if a tile is a water tile
func is_water_tile(tile_id: int) -> bool:
	return tile_id == WATER_TILE_ID

# Check if there is a structure on the tile
func is_structure(tile_pos: Vector2i) -> bool:
	var tilemap: TileMap = get_node("/root/MapManager/TileMap")
	var structures = get_tree().get_nodes_in_group("structures")
	for structure in structures:
		var structure_tile_pos = tilemap.local_to_map(structure.global_position)
		if tile_pos == structure_tile_pos:
			return true
	return false

# Check if there is a unit on the tile
func is_unit_present(tile_pos: Vector2i) -> bool:
	var tilemap: TileMap = get_node("/root/MapManager/TileMap")
	var all_units = get_tree().get_nodes_in_group("player_units") + get_tree().get_nodes_in_group("zombies")
	for unit in all_units:
		var unit_tile_pos = tilemap.local_to_map(unit.global_position)
		if tile_pos == unit_tile_pos:
			return true
	return false

# Check if there is a unit on the tile
func is_zombie_present(tile_pos: Vector2i) -> bool:
	var tilemap: TileMap = get_node("/root/MapManager/TileMap")
	var all_units = get_tree().get_nodes_in_group("zombies")
	for unit in all_units:
		var unit_tile_pos = tilemap.local_to_map(unit.global_position)
		if tile_pos == unit_tile_pos:
			return true
	return false

func fade_out(sprite: Node, duration: float = 1) -> void:
	"""
	Fades the sprite out over the specified duration.
	:param sprite: The sprite to fade out.
	:param duration: The time it takes to fade out.
	"""
	if not sprite:
		print("Error: Sprite is null!")
		return

	# If the sprite is already faded out, do nothing
	if sprite.modulate.a <= 0.0:
		return

	# Create a new tween for the fade-out animation
	var tween = create_tween()

	#Play SFX
	get_parent().get_child(2).stream = get_parent().invisibility_audio
	get_parent().get_child(2).play()

	# Tween the alpha value of the sprite's modulate property to 0
	tween.tween_property(sprite, "modulate:a", 0.2, duration)

	# Wait for the tween to finish
	await tween.finished

func fade_in(sprite: Node, duration: float = 1) -> void:
	"""
	Fades the sprite in over the specified duration.
	:param sprite: The sprite to fade in.
	:param duration: The time it takes to fade in.
	"""
	
	# Camera focuses on the active zombie
	var camera: Camera2D = get_node("/root/MapManager/Camera2D")
	camera.focus_on_position(get_parent().position)
		
	if not sprite:
		print("Error: Sprite is null!")
		return

	# If the sprite is already fully visible, do nothing
	if sprite.modulate.a >= 1:
		return

	# Create a new tween for the fade-in animation
	var tween = create_tween()

	#Play SFX
	get_parent().get_child(2).stream = get_parent().invisibility_audio
	get_parent().get_child(2).play()

	# Tween the alpha value of the sprite's modulate property to 1
	tween.tween_property(sprite, "modulate:a", 1.0, duration)

	# Wait for the tween to finish
	await tween.finished
	
func is_mouse_over_gui() -> bool:
	# Get global mouse position
	var mouse_pos = get_viewport().get_mouse_position()

	# Get all nodes in the "hud_controls" group
	var hud_controls = get_tree().get_nodes_in_group("portrait_controls") + get_tree().get_nodes_in_group("hud_controls")
	for control in hud_controls:
		if control is TextureRect or Button and control.is_visible_in_tree():
			# Use global rect to check if mouse is over the button
			var rect = control.get_global_rect()
			print("Checking button:", control.name, "Rect:", rect, "Mouse Pos:", mouse_pos)
			if rect.has_point(mouse_pos):
				print("Mouse is over button:", control.name, "Rect:", rect, "Mouse Pos:", mouse_pos)
				return true
	print("Mouse is NOT over any button.")
	return false

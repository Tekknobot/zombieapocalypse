extends Node2D

@export var laser_color_1: Color = Color(1, 0, 0, 1)  # First color
@export var laser_color_2: Color = Color(0, 1, 0, 1)  # Second color
@export var laser_color_3: Color = Color(0, 0, 1, 1)  # Third color

@export var laser_width: float = 5.0  # Default width of the laser
@export var laser_length: float = 300.0  # Max length of the laser
@export var pulse_duration: float = 0.15  # Time between pulses

@onready var line = $Line2D  # Line2D node for the laser
@export var hover_tile_path: NodePath = "/root/MapManager/HoverTile"
@onready var hover_tile = get_node_or_null(hover_tile_path)

var explosion_scene = preload("res://assets/scenes/vfx/explosion.tscn")
var camera_flag: bool = true

# Animation state variables
var color_timer: Timer
var width_pulse_up: bool = true
var pulse_speed: float = 5.0  # Speed of pulsing
var color_cycle: Array  # Array to store the three colors
var current_color_index: int = 0  # Index for cycling through colors
var laser_segments: Array = []  # Store references to all laser segments
var current_segment_index: int = 0  # Tracks the segment being animated

var laser_deployed: bool = false
var pulsing_segments: Array = []  # Array to track which segments are pulsing
var explosion_target

# Create the timer for the pulse effect
var pulse_timer = Timer.new()
var spark_emitter = preload("res://assets/scenes/vfx/sparks.tscn")  # Reference to the particle emitter
var spark_scene
var segment
var current_segment

func _ready():
	# Initialize color cycle
	color_cycle = [laser_color_1, laser_color_2, laser_color_3]
	
	# Set up the laser
	line.width = laser_width
	line.default_color = laser_color_1  # Start with the first color
	line.visible = false  # Hide laser initially

	pulse_timer.wait_time = pulse_duration
	pulse_timer.one_shot = false
	pulse_timer.connect("timeout", Callable(self, "_on_pulse_timer_timeout"))
	add_child(pulse_timer)
	pulse_timer.start()
	
	if spark_emitter:
		spark_scene = spark_emitter.instantiate()
		add_child(spark_scene)
		spark_scene.emitting = false  # Start with no particles
		
func _process(delta):
	is_mouse_over_gui()
	
func _input(event):
	# Check for mouse click
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# Block gameplay input if the mouse is over GUI
		if is_mouse_over_gui():
			print("Input blocked by GUI.")
			return  # Prevent further input handling

		# Ensure the mouse position is within map boundaries
		var tilemap: TileMap = get_node("/root/MapManager/TileMap")
		var map_size = tilemap.get_used_rect()  # Get the map's used rectangle
		var map_width = map_size.size.x
		var map_height = map_size.size.y

		# Convert the mouse global position to tile coordinates
		var mouse_local = tilemap.local_to_map(get_global_mouse_position())

		# Check if the mouse position is outside map bounds
		if mouse_local.x < 0 or mouse_local.x >= map_width or mouse_local.y < 0 or mouse_local.y >= map_height:
			return  # Exit the function if the mouse is outside the map
			
		# Ensure hover_tile exists and "Sarah Reese" is selected
		if hover_tile and hover_tile.selected_player and hover_tile.selected_player.player_name == "Sarah. Reese" and 	GlobalManager.thread_toggle_active == true:
			#var tilemap: TileMap = get_node("/root/MapManager/TileMap")
			var mouse_position = get_global_mouse_position() 
			mouse_position.y += 8
			var mouse_pos = tilemap.local_to_map(mouse_position)
			var laser_target = tilemap.map_to_local(mouse_pos)
			laser_target.y -= 8
			explosion_target = laser_target
			deploy_laser(laser_target)

func deploy_laser(target_position: Vector2):
	# Clear previous laser segments
	laser_segments.clear()  # Clear the list of segments
	for child in get_children():
		if child is Line2D:
			child.queue_free()	
			
	# Camera focus
	var camera: Camera2D = get_node("/root/MapManager/Camera2D")
	camera_flag = true
	camera.zoom_speed = 5

	get_parent().get_child(0).play("attack")
	
	# Get the current facing direction of the parent (1 for right, -1 for left)
	var current_facing = 1 if get_parent().scale.x > 0 else -1

	# Determine sprite flip based on target_position relative to the parent
	if target_position.x > global_position.x and current_facing == 1:
		get_parent().scale.x = -abs(get_parent().scale.x)  # Flip to face left
	elif target_position.x < global_position.x and current_facing == -1:
		get_parent().scale.x = abs(get_parent().scale.x)  # Flip to face right

	# Calculate laser path across tiles
	var tilemap: TileMap = get_node("/root/MapManager/TileMap")

	# Get cell size from the tilemap
	var cell_size = Vector2(32, 32)
	
	var start = tilemap.local_to_map(Vector2(global_position.x, global_position.y - 16))
	start = Vector2i(start.x - 1, start.y)
	var end = tilemap.local_to_map(Vector2(target_position.x, target_position.y - 16))

	# Use a Bresenham line algorithm to get all tiles along the laser path
	var tiles = get_line_tiles(start, end)
	

	# Create a Line2D for each tile, layered correctly
	for i in range(tiles.size() - 1):
		var tile_pos = tiles[i]
		var segment_start = tilemap.map_to_local(tile_pos) + cell_size / 2
		var segment_end = tilemap.map_to_local(tiles[i + 1]) + cell_size / 2
		
		var height_offset = 0
		var segment_color = color_cycle[current_color_index]  # Default color from cycle

		# Create a Line2D node for this segment
		segment = Line2D.new()
		add_child(segment)
		laser_segments.append(segment)  # Store the segment reference

		var segment_rect = Rect2(segment.global_position, Vector2(32, 32))  # Create the rect with the correct position and size

		# Check overlap with structures
		var structures = get_tree().get_nodes_in_group("structures")
		for structure in structures:
			if Rect2(structure.global_position, Vector2(32, 32)).intersects(segment_rect):
				segment_color = laser_color_3
				height_offset = structure.layer

		# Check overlap with units
		var all_units = get_tree().get_nodes_in_group("player_units") + get_tree().get_nodes_in_group("zombies")
		for unit in all_units:
			if Rect2(unit.global_position, Vector2(32, 32)).intersects(segment_rect):
				segment_color = laser_color_3
				height_offset = unit.layer

		# Update z_index for layering based on tile position and height offset
		segment.z_index = (tile_pos.x + tile_pos.y) - height_offset

		segment.width = laser_width
		segment.default_color = segment_color  # Apply the determined color

		# Add points to the Line2D
		segment.add_point(to_local(segment_start))
		segment.add_point(to_local(segment_end))

	laser_deployed = true
	
	#Play SFX
	get_parent().get_child(2).stream = get_parent().spider_strand_audio
	get_parent().get_child(2).play()
	
func _on_pulse_timer_timeout():
	if laser_segments.is_empty():
		return  # Skip if there are no laser segments

	if current_segment_index >= laser_segments.size():
		current_segment_index = 0  # Reset to the first segment

	# Reset all segments to their default state
	for segment in laser_segments:
		segment.width = laser_width
		segment.default_color = color_cycle[current_color_index]

	# Apply the pulse effect to the current segment
	var current_segment = laser_segments[current_segment_index]
	current_segment.width = laser_width * 1  # Start with increased width
	current_segment.default_color = laser_color_3  # Use the third color for the pulse

	# Move the spark emitter to the current segment
	if spark_scene:  # Ensure the spark emitter exists
		get_parent().get_child(0).play("attack")
		var spark_position = current_segment.to_global(current_segment.get_point_position(0))  # Get start of the segment
		spark_scene.global_position = spark_position
		spark_scene.emitting = true  # Start emitting particles

		# Camera focuses on the active zombie
		var camera: Camera2D = get_node("/root/MapManager/Camera2D")
		camera.focus_on_position(spark_position) 	

	# Check if the current segment is the last one
	if current_segment_index == laser_segments.size() - 1:  # Last segment
		# Get the endpoint of the last segment and trigger the explosion
		var last_point = current_segment.to_global(current_segment.get_point_position(1))
		_trigger_explosion(explosion_target)
		get_parent().get_child(0).play("default")

		# Reset spark emitter after finishing
		if spark_scene:
			spark_scene.emitting = false  # Stop emitting particles

		# Reset the segment index
		current_segment_index = 0

	# Move to the next segment
	current_segment_index += 1
	
func get_line_tiles(start: Vector2i, end: Vector2i) -> Array:
	var tiles = []
	var dx = abs(end.x - start.x)
	var dy = abs(end.y - start.y)
	var sx = 1 if start.x < end.x else -1
	var sy = 1 if start.y < end.y else -1
	var err = dx - dy

	var current = start
	while current != end:
		tiles.append(current)
		var e2 = err * 2
		if e2 > -dy:
			err -= dy
			current.x += sx
		if e2 < dx:
			err += dx
			current.y += sy

	tiles.append(end)  # Include the last tile
	return tiles

# Trigger explosion at the target position after the missile reaches it
func _trigger_explosion(last_point: Vector2):
	print("Explosion triggered at position:", last_point)
	
	# Instantiate the explosion effect at the target's position
	var explosion_instance = explosion_scene.instantiate()
	get_parent().add_child(explosion_instance)
	last_point.y += 8
	explosion_instance.global_position = last_point
	print("Explosion instance added to scene at:", last_point)
	
	# Explosion radius (adjust this as needed)
	var explosion_radius = 8

	# Variable to track if XP should be added (only once per explosion)
	var xp_awarded = false

	# Check for PlayerUnit within explosion radius
	for player in get_tree().get_nodes_in_group("player_units"):
		if player.position.distance_to(last_point) <= explosion_radius:	
			player.flash_damage()
			player.apply_damage(player.attack_damage)
			player.clear_movement_tiles()
					
			xp_awarded = true  # Mark XP as earned for this explosion

			var hud_manager = get_node("/root/MapManager/HUDManager")
			hud_manager.update_hud(player)
			clear_segments()

	# Check for ZombieUnit within explosion radius
	for zombie in get_tree().get_nodes_in_group("zombies"):
		if zombie.position.distance_to(last_point) <= explosion_radius:	
			zombie.flash_damage()
			for player in get_tree().get_nodes_in_group("player_units"):
				if player.player_name == "Sarah. Reese":
					zombie.apply_damage(player.attack_damage)
					zombie.clear_movement_tiles()
					
			xp_awarded = true  # Mark XP as earned for this explosion

			var hud_manager = get_node("/root/MapManager/HUDManager")
			hud_manager.update_hud_zombie(zombie)
			clear_segments()
			
	# Check for Structures within explosion radius
	for structure in get_tree().get_nodes_in_group("structures"):
		if structure.position.distance_to(last_point) <= explosion_radius:
			structure.get_child(0).play("demolished")  # Play "collapse" animation if applicable
			print("Structure removed from explosion")
			xp_awarded = true  # Mark XP as earned for this explosion
			clear_segments()
			
	# Add XP if at least one target was hit
	if xp_awarded:
		await get_tree().create_timer(1).timeout
		add_xp()	
				
	clear_segments()	

	var hud_manager = get_parent().get_parent().get_parent().get_node("HUDManager")  # Adjust the path if necessary
	hud_manager.hide_special_buttons()	
	
	# Access the 'special' button within HUDManager
	GlobalManager.thread_toggle_active = false  # Deactivate the special toggle
	hud_manager.thread.button_pressed = false
	self.get_parent().has_attacked = true
	self.get_parent().has_moved = true
	get_parent().check_end_turn_conditions()		
				
func add_xp():
	# Add XP
	# Access the HUDManager (move up the tree from PlayerUnit -> UnitSpawn -> parent to HUDManager)
	var hud_manager = get_node("/root/MapManager/HUDManager")  # Adjust the path if necessary
	
	# Get all nodes in the 'hovertile' group
	var hover_tiles = get_tree().get_nodes_in_group("hovertile")
	# Iterate through the list and find the HoverTile node
	for hover_tile in hover_tiles:
		if hover_tile.name == "HoverTile":
			# Check if 'last_selected_player' exists and has 'current_xp' property
			if hover_tile.selected_player or hover_tile.selected_structure or hover_tile.selected_zombie:
				hover_tile.selected_player.current_xp += 25
				# Update the HUD to reflect new stats
				hud_manager.update_hud(hover_tile.selected_player)	
				print("Added 25 XP to", hover_tile.selected_player, "new XP:", hover_tile.selected_player.current_xp)		

				# Optional: Check for level up, if applicable
				if hover_tile.selected_player.current_xp >= hover_tile.selected_player.xp_for_next_level:
					hover_tile.selected_player.level_up()			
			else:
				print("last_selected_player does not exist.")

	hud_manager.update_hud(hover_tile.selected_player)

func clear_segments():
	# Clear previous laser segments
	laser_segments.clear()  # Clear the list of segments
	for child in get_children():
		if child is Line2D:
			child.queue_free()		

func is_mouse_over_gui() -> bool:
	# Get global mouse position
	var mouse_pos = get_viewport().get_mouse_position()

	# Get all nodes in the "hud_controls" group
	var hud_controls = get_tree().get_nodes_in_group("hud_controls")
	for control in hud_controls:
		if control is Button:
			# Use global rect to check if mouse is over the button
			var rect = control.get_global_rect()
			print("Checking button:", control.name, "Rect:", rect, "Mouse Pos:", mouse_pos)
			if rect.has_point(mouse_pos):
				print("Mouse is over button:", control.name, "Rect:", rect, "Mouse Pos:", mouse_pos)
				return true
	print("Mouse is NOT over any button.")
	return false
extends Node2D

@onready var map_fader = get_node("/root/MapManager/MapFader")
@onready var hud_manager = get_node("/root/MapManager/HUDManager")

@onready var audio_player = $AudioStreamPlayer2D
@export var gameover_audio = preload("res://audio/SFX/fast-game-over.wav")

var gameover : bool = false
var map_cleared : bool = false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.

# Called every frame. 'delta' is the elapsed time since the previous frame.
func check_mission_manager():
	if GlobalManager.secret_item_destroyed or GlobalManager.players_killed:
		audio_player.stream = gameover_audio
		audio_player.play()
		
		hud_manager.visible = false
		map_fader.fade_in()
		
		gameover = true
		
	if GlobalManager.zombies_cleared and GlobalManager.secret_item_found:		
		hud_manager.visible = false
		map_fader.fade_in()		
		
		map_cleared = true
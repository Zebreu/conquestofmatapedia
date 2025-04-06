extends Node2D # Or CanvasLayer

@export var background_texture: Texture2D

func _ready():
	if background_texture:
		var background = TextureRect.new()
		background.texture = background_texture
		# Set the stretch mode to cover the entire viewport
		background.stretch_mode = TextureRect.STRETCH_SCALE
		# Set the size to the viewport size
		background.size = get_viewport_rect().size
		# Ensure the background is behind other nodes (optional, but often desired)
		background.z_index = -1
		add_child(background)
	else:
		printerr("Error: No background texture assigned in the Inspector.")

func _on_viewport_resized():
	# Update the background size if the viewport is resized
	if has_node("TextureRect"):
		get_node("TextureRect").size = get_viewport_rect().size

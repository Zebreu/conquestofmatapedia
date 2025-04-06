extends Node2D

# --- Configuration ---
#@export var server_url = "ws://localhost:7171/ws"
@export var server_url = "ws://35.192.119.50:7171/ws"
# https://97dc-142-180-221-157.ngrok-free.app/
# Or if running server on a different machine/container:
# @export var server_url = "ws://<your_server_ip>:8000/ws"

# --- Internal State ---
var _peer: WebSocketPeer = null # The actual WebSocket peer object
var _is_connected = false
var _click_history = [] # Stores the history received from the server
var _previous_state = WebSocketPeer.STATE_CLOSED # Track state changes

# Color for drawing clicks
const CLICK_COLOR = Color.RED
const CLICK_RADIUS = 5.0

# --- Godot Lifecycle Methods ---

func _ready():
	print("Click Client starting (Godot 4.3+)...")
	_connect_to_server()

func _process(_delta):
	# WebSocketPeer requires polling to process network events
	if _peer == null:
		return # Not initialized yet

	_peer.poll() # Essential!

	var current_state = _peer.get_ready_state()

	# --- State Change Detection ---
	if current_state != _previous_state:
		match current_state:
			WebSocketPeer.STATE_OPEN:
				_handle_connected()
			WebSocketPeer.STATE_CLOSING:
				print("WebSocket closing...")
			WebSocketPeer.STATE_CLOSED:
				_handle_disconnected(_peer.get_close_code(), _peer.get_close_reason())
		_previous_state = current_state # Update tracked state

	# --- Data Receiving ---
	if current_state == WebSocketPeer.STATE_OPEN:
		while _peer.get_available_packet_count() > 0:
			# ---- CORRECTED CODE ----
			var packet_bytes : PackedByteArray = _peer.get_packet()
			var packet_string : String = packet_bytes.get_string_from_utf8()
			# ---- END CORRECTION ----
			_handle_data_received(packet_string)

func _exit_tree():
	# Clean up the connection when the node is removed or the game closes
	if _peer != null and _peer.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		print("Closing WebSocket connection on exit.")
		_peer.close()


func _input(event):
	# Check if it's a left mouse button click press
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if not _is_connected or _peer == null or _peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
			print("Not connected to server. Click not sent.")
			return

		var click_pos = event.position
		print("Clicked at: ", click_pos)

		# Prepare data payload as a Dictionary
		var click_data = {
			"x": click_pos.x,
			"y": click_pos.y,
			"comment": "Clicked from Godot 4.3+!" # Example extra data
		}

		# Convert Dictionary to JSON string
		var json_string = JSON.stringify(click_data)

		# Send the JSON string over WebSocket using send_text
		var err = _peer.send_text(json_string)
		if err != OK:
			printerr("Error sending click data: ", err)
		else:
			print("Sent click data: ", json_string)


# --- Drawing Clicks ---
func _draw():
	# Draw circles for each click in the history
	for click_event in _click_history:
		# Ensure the click data has 'x' and 'y' keys, handle potential non-numeric data
		if click_event.data.has("x") and str(click_event.data.x).is_valid_float() and \
		   click_event.data.has("y") and str(click_event.data.y).is_valid_float():
			var pos = Vector2(float(click_event.data.x), float(click_event.data.y))
			draw_circle(pos, CLICK_RADIUS, CLICK_COLOR)
		else:
			printerr("Skipping drawing click due to invalid/missing coordinates: ", click_event)


# --- Helper Functions ---

func _connect_to_server():
	print("Attempting to connect to: ", server_url)
	_peer = WebSocketPeer.new() # Create the peer object
	var err = _peer.connect_to_url(server_url)
	if err != OK:
		printerr("Error initiating connection: ", err)
		_is_connected = false
		_peer = null # Failed to even start connecting
	else:
		print("Connection initiation successful, waiting for state change...")
		_previous_state = _peer.get_ready_state() # Initial state (likely CONNECTING)


func _handle_connected():
	"""Called when the WebSocket state transitions to OPEN."""
	_is_connected = true
	print("Successfully connected to server: ", server_url)
	# Optional: Improve responsiveness, usually default is fine
	# _peer.set_no_delay(true)


func _handle_disconnected(code = -1, reason = ""):
	"""Called when the WebSocket state transitions to CLOSED."""
	_is_connected = false
	if code != -1:
		print("WebSocket connection closed. Code: %d, Reason: %s" % [code, reason])
	else:
		# Could be a connection failure before opening
		printerr("WebSocket connection failed or closed unexpectedly.")
	_peer = null # Discard the old peer
	# Optional: Implement retry logic here
	# print("Attempting to reconnect in 5 seconds...")
	# await get_tree().create_timer(5.0).timeout
	# _connect_to_server()


func _handle_data_received(packet_string : String):
	"""Parses and processes incoming JSON data."""
	print("Data received from server.")

	# Parse the JSON string
	var json = JSON.new()
	var error = json.parse(packet_string)

	if error != OK:
		printerr("Error parsing JSON from server: ", json.get_error_message(), " at line ", json.get_error_line())
		printerr("Received raw data: ", packet_string)
		return

	var received_data = json.get_data()

	if received_data is Dictionary and received_data.has("type") and received_data.has("history"):
		# Expecting format: {"type": "init" or "update", "history": [...]}
		print("Received message type: ", received_data.type)
		if received_data.history is Array: # Basic type check
			_click_history = received_data.history
			print("Updated click history count: ", _click_history.size())
			# Trigger a redraw to show the updated clicks
			queue_redraw()
		else:
			printerr("Received 'history' but it wasn't an array: ", typeof(received_data.history))
	else:
		print("Received unexpected data format: ", received_data)

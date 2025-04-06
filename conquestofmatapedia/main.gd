extends Node2D

# --- Configuration ---
#@export var server_base_url = "http://127.0.0.1:7171"
@export var server_base_url = "http://35.192.119.50:7171/"
# 97dc-142-180-221-157.ngrok-free.app:7171
# Or if running server on a different machine/container:
# @export var server_base_url = "http://<your_server_ip>:8000"

# --- Node References ---
# Use @onready to ensure the nodes are available when needed
@onready var http_request: HTTPRequest = $ClickRequest
@onready var poll_timer: Timer = $PollTimer

# --- Internal State ---
var _click_history = [] # Stores the history received from the server
var _is_request_pending = false # Prevent overlapping requests

# Color for drawing clicks
const CLICK_COLOR = Color.DEEP_PINK # Changed color to distinguish from WS version
const CLICK_RADIUS = 5.0

# --- Godot Lifecycle Methods ---

func _ready():
	print("HTTP Click Client starting...")
	# Connect the HTTPRequest node's signal to our handler function
	http_request.request_completed.connect(_on_request_completed)
	# Connect the Timer's signal to trigger polling
	poll_timer.timeout.connect(_on_poll_timer_timeout)

	# Fetch initial history when the game starts
	_fetch_history_request()

func _input(event):
	# Check if it's a left mouse button click press
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var click_pos = event.position
		print("Clicked at: ", click_pos)

		# Prepare data payload as a Dictionary
		var click_data = {
			"x": click_pos.x,
			"y": click_pos.y,
			"comment": "Clicked from Godot (HTTP)!"
		}
		# Send the click data via HTTP POST
		_send_click_request(click_data)

# --- Drawing Clicks ---
func _draw():
	# Draw circles for each click in the history
	for click_event in _click_history:
		# Add more robust checking for dictionary and key existence
		if typeof(click_event) == TYPE_DICTIONARY and click_event.has("data") and \
		   typeof(click_event.data) == TYPE_DICTIONARY and \
		   click_event.data.has("x") and str(click_event.data.x).is_valid_float() and \
		   click_event.data.has("y") and str(click_event.data.y).is_valid_float():
			var pos = Vector2(float(click_event.data.x), float(click_event.data.y))
			draw_circle(pos, CLICK_RADIUS, CLICK_COLOR)
		else:
			printerr("Skipping drawing click due to invalid format: ", click_event)

# --- HTTP Request Logic ---

func _fetch_history_request():
	"""Initiates a GET request to fetch the click history."""
	if _is_request_pending:
		print("Request already pending, skipping fetch history.")
		return

	print("Fetching click history...")
	_is_request_pending = true
	var url = "%s/clicks" % server_base_url
	# request(url, custom_headers, method, request_data)
	var error = http_request.request(url, [], HTTPClient.METHOD_GET, "")
	if error != OK:
		printerr("Error starting GET request: ", error)
		_is_request_pending = false

func _send_click_request(click_payload: Dictionary):
	"""Initiates a POST request to send click data."""
	if _is_request_pending:
		print("Request already pending, skipping send click.")
		# Optionally queue the click to send later
		return

	print("Sending click data...")
	_is_request_pending = true
	var url = "%s/click" % server_base_url
	var headers = ["Content-Type: application/json"]
	var body = JSON.stringify(click_payload)

	# request(url, custom_headers, method, request_data)
	var error = http_request.request(url, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		printerr("Error starting POST request: ", error)
		_is_request_pending = false


# --- Signal Handlers ---

func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	"""Handles the completion of any HTTP request made by the ClickRequest node."""
	_is_request_pending = false # Allow new requests
	print("HTTP Request completed. Result: %d, Code: %d" % [result, response_code])

	if result != HTTPRequest.RESULT_SUCCESS:
		printerr("HTTP Request failed! Result code: ", result)
		return

	if response_code >= 400:
		printerr("HTTP Error! Response code: ", response_code)
		printerr("Response body: ", body.get_string_from_utf8())
		return

	# --- Process successful response ---
	var response_string = body.get_string_from_utf8()
	var json = JSON.new()
	var error = json.parse(response_string)

	if error != OK:
		printerr("Error parsing JSON response: ", json.get_error_message())
		printerr("Raw response: ", response_string)
		return

	var parsed_data = json.get_data()

	# Check if the response seems to be the history data (from GET /clicks)
	if parsed_data is Dictionary and parsed_data.has("history") and parsed_data.history is Array:
		print("Received history update.")
		_click_history = parsed_data.history
		queue_redraw() # Update the visual display
	# Check if the response is from the POST /click endpoint (simple success message)
	elif parsed_data is Dictionary and parsed_data.has("message") and parsed_data.message == "Click received and broadcasted":
		print("Server confirmed click received.")
		# Optional: Immediately fetch history again for faster feedback after POST
		# _fetch_history_request() # Be careful not to cause request loops if errors occur
	else:
		print("Received unrecognized successful response: ", parsed_data)


func _on_poll_timer_timeout():
	"""Called periodically by the Timer to fetch updates."""
	print("Poll timer timeout, fetching history...")
	_fetch_history_request()

import asyncio
import uvicorn
from fastapi import FastAPI, WebSocket, WebSocketDisconnect, Body
from typing import List, Dict, Any

# --- Configuration ---
HOST = "0.0.0.0"  # Listen on all network interfaces
PORT = 7171

# --- Application Setup ---
app = FastAPI(title="Game Server (HTTP + WebSocket)")

# --- Global State ---
# Stores the history of all clicks received { "client_id": str | int, "data": Any }
click_history: List[Dict[str, Any]] = []
# Stores active WebSocket connections
active_connections: List[WebSocket] = []

# --- Helper Functions ---
async def broadcast_state():
    """Sends the entire click history to all connected WebSocket clients."""
    disconnected_clients = []
    # Create a snapshot of the history to send
    # Ensures consistency if history changes during broadcast loop (though unlikely here)
    current_history = list(click_history)
    message = {"type": "update", "history": current_history}

    for connection in active_connections:
        try:
            await connection.send_json(message)
        except RuntimeError: # Catch errors if send fails (e.g., connection closed abruptly)
            disconnected_clients.append(connection)
        except Exception: # Catch other potential WebSocket errors during send
            disconnected_clients.append(connection)

    # Clean up disconnected clients found during broadcast
    for client in disconnected_clients:
        if client in active_connections:
            active_connections.remove(client)
            print(f"WS Client {id(client)} removed due to broadcast error.")


# --- WebSocket Endpoint ---
@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    """Handles WebSocket connections, receives clicks, and broadcasts updates."""
    await websocket.accept()
    client_id = id(websocket) # Simple unique ID for this connection
    active_connections.append(websocket)
    print(f"WS Client {client_id} connected. Total WS clients: {len(active_connections)}")

    try:
        # Send initial state to the newly connected client
        await websocket.send_json({"type": "init", "history": list(click_history)})

        while True:
            # Wait for a message (click data) from the client
            # Expecting JSON like: {"x": 100, "y": 200} or similar
            data = await websocket.receive_json()
            print(f"Received click via WS from {client_id}: {data}")

            # Add the received click data along with client identifier to the history
            click_data = {"client_id": client_id, "data": data, "source": "websocket"}
            click_history.append(click_data)

            # Broadcast the updated history to ALL connected clients
            await broadcast_state()

    except WebSocketDisconnect:
        print(f"WS Client {client_id} disconnected.")
    except Exception as e:
        # Catch potential errors like invalid JSON
        print(f"Error with WS client {client_id}: {e}")
    finally:
        # Ensure cleanup happens regardless of how the loop exits
        if websocket in active_connections:
            active_connections.remove(websocket)
        print(f"WS Client {client_id} connection closed. Total WS clients: {len(active_connections)}")
        # Optional: Broadcast user left event if needed


# --- HTTP Endpoints ---

@app.get("/clicks")
async def get_clicks():
    """HTTP GET endpoint to retrieve the current click history."""
    return {"history": click_history}

# Example using Body for explicit request body definition
# You could also use Pydantic models here for better validation
@app.post("/click")
async def post_click(click_data: Dict[str, Any] = Body(...)):
    """HTTP POST endpoint to submit a new click."""
    print(f"Received click via HTTP POST: {click_data}")

    # Add the click to history, marking its source
    # Using a fixed identifier for HTTP POSTs
    new_click = {"client_id": "http_poster", "data": click_data, "source": "http"}
    click_history.append(new_click)

    # IMPORTANT: Broadcast the state change to all connected WebSocket clients
    await broadcast_state()

    return {"message": "Click received and broadcasted", "click_added": new_click}


@app.get("/")
async def get_root():
    """Simple HTTP endpoint to show the server is running."""
    return {"message": "Game Server is running",
            "websocket_endpoint": "/ws",
            "http_get_clicks": "/clicks",
            "http_post_click": "/click"}

# --- Server Execution ---
if __name__ == "__main__":
    print(f"Starting server on {HOST}:{PORT}")
    # Use uvicorn to run the FastAPI application
    uvicorn.run("__main__:app", host=HOST, port=PORT, reload=True)

# --- How to Run ---
# 1. Save this code as a Python file (e.g., `server.py`).
# 2. Make sure you have FastAPI and Uvicorn installed:
#    `pip install fastapi uvicorn websockets`
# 3. Run the server from your terminal:
#    `uvicorn server:app --host 0.0.0.0 --port 8000 --reload`
#
# --- How to Interact ---
# - WebSocket Clients: Connect to `ws://<server_ip>:8000/ws`.
#   - Listen for JSON messages (`{"type": "init", "history": [...]}` or `{"type": "update", "history": [...]}`).
#   - Send JSON messages for clicks (e.g., `{"x": 123, "y": 456}`).
# - HTTP Clients:
#   - GET `http://<server_ip>:8000/clicks` to retrieve the current click history.
#   - POST to `http://<server_ip>:8000/click` with a JSON body representing the click (e.g., `{"button": "left", "timestamp": 1678886 B400}`).
#     - Example using curl:
#       `curl -X POST -H "Content-Type: application/json" -d '{"x": 50, "y": 50}' http://localhost:8000/click`
#
# Note: Clicks added via the HTTP POST endpoint will trigger an update broadcast
# to all connected WebSocket clients.
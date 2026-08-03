# LTD

A small multiplayer prototype: a Godot 4 client (HTML5-exportable) plus an authoritative Node.js WebSocket server.

## How it works

- Up to **4 players** connect; join order assigns their color: **Red, Blue, White, Black**. A 5th connection is rejected.
- Players are cubes (1.0 units) on a grey 40x40 plane, viewed by a shared static top-down camera pitched at 70 degrees.
- **Click the plane** to move your cube to that spot (movement is simulated on the server at 8 units/s).
- While at least one client is connected, the server keeps one small **yellow cube** (0.5 units) alive. If nobody picks it up within **5 seconds**, it respawns at a new random location.
- Walk over the yellow cube to pick it up: **+1 point**, and a new cube spawns immediately. Only one player can claim each cube (server resolves ties).
- The server owns all state: positions, spawns, and scores. The client only sends `join` and `move` and renders the broadcast state (20 Hz).

## Running the server

Requires Node.js.

```bash
cd server
npm install
npm start
```

Listens on `ws://0.0.0.0:8765`.

## Running the client

Open the project in Godot 4.7 and press Play (`main.tscn` is the main scene), or export it for Web:

1. Project > Export > Add... > **Web**
2. Export the project and serve the output folder over HTTP (Godot's "Remote Debug > Run in Browser" also works).

In the client, enter the server IP (`127.0.0.1` locally), port (`8765`), and a name, then press **Connect**.

Note for Web builds: a page served over **https** can only open **wss** (secure WebSocket) connections. For LAN/localhost testing, serve the exported page over plain **http**.

## Protocol (JSON over WebSocket)

Client to server: `{type:"join", name}` and `{type:"move", x, z}`.
Server to client: `welcome {id, color}`, `full`, `pickup {id, name, score}`, and `state {players:[{id,name,color,x,z,score}], cube:{x,z}|null}`.

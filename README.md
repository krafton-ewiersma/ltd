# LTD

A small multiplayer prototype: a Godot 4 client (HTML5-exportable) plus an authoritative Node.js WebSocket server.

## How it works

- Up to **4 players** connect; join order assigns their color: **Red, Blue, White, Black**. A 5th connection is rejected.
- Players are cubes (1.0 units) on a grey 40x40 plane, viewed by a shared static top-down camera pitched at 70 degrees.
- **Click the plane** to move your cube to that spot (movement is simulated on the server at 8 units/s).
- While at least one client is connected, the server keeps one small **yellow cube** (0.5 units) alive. If nobody picks it up within **5 seconds**, it respawns at a new random location.
- Walk over the yellow cube to pick it up: **+1 point**, and a new cube spawns immediately. Only one player can claim each cube (server resolves ties).
- The server owns all state: positions, spawns, and scores. The client only sends `join` and `move` and renders the broadcast state (20 Hz).

## Quick start

Requires Node.js. First time only:

```bash
cd server
npm install
```

Then double-click **`server.bat`** (project root). It opens two console windows:

- **Game server** — `node server.js`, WebSocket on port **8765**. All clients connect here.
- **Web server** — `node serve-web.js`, serves the exported web build from `build/web/` at <http://localhost:8080>.

Or run them individually: `npm start` (game server) / `npm run web` (web build server) from the `server` folder.

In the client, enter the server IP (`127.0.0.1` locally), port (`8765`), and a name, then press **Connect**.

## Running the client

Three ways to get a client:

- **Editor**: open the project in Godot 4.7 and press Play (`main.tscn` is the main scene).
- **Browser**: with `server.bat` running, open <http://localhost:8080> (uses the exported build in `build/web/`).
- **Multiple local clients**: in the editor, Debug > **Customize Run Instances...** > Enable Multiple Instances (up to 4). Browser tabs and editor instances can join the same match.

## Web export

The `Web` export preset (`export_presets.cfg`) is already configured:

- Thread support **off**, so the build runs from any plain HTTP server (no cross-origin isolation headers needed).
- `exclude_filter` keeps `server/*` and `key.key` out of the shipped pack.
- Output goes to `build/web/` (git-ignored; the `build/.gdignore` stops Godot importing its own export output).

Rebuild after changes with Project > Export in the editor, or headless:

```bash
engine\Godot_v4.7.1-stable_win64.exe --headless --path . --export-release "Web" build/web/index.html
```

Export templates for 4.7.1 must be installed (Editor > Manage Export Templates, only the web templates are needed).

Note for Web builds: a page served over **https** can only open **wss** (secure WebSocket) connections. For LAN/localhost testing, serve the exported page over plain **http**. The exported page can be hosted anywhere (e.g. itch.io); it only needs to reach the game server's IP and port.

## Protocol (JSON over WebSocket)

Client to server: `{type:"join", name}` and `{type:"move", x, z}`.
Server to client: `welcome {id, color}`, `full`, `pickup {id, name, score}`, and `state {players:[{id,name,color,x,z,score}], cube:{x,z}|null}`.

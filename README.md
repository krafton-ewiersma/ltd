# LTD

A small multiplayer prototype: a Godot 4 client (HTML5-exportable) plus an authoritative Node.js WebSocket server.

## How it works

- Players connect with a **unique name**, then land in the **lobby**: game rooms on the left (refreshed every second), connected players top right, chat bottom right.
- **Game rooms** hold up to **8 members** (bots count). Join order assigns colors: Red, Blue, White, Black, Green, Orange, Purple, Cyan. Anyone can create a room with a name, optional password, and a max score of 10-50 (default 20).
- On launch the server seeds **4 bot rooms** (1, 3, 5 and 7 bots) named randomly from the reserved list: *Litha, Lughnasa, Mabon, Samhain, Yule, Imbolc, Ostara, Beltane*. Those names can't be used by players or user rooms.
- **Bots** (`server/bots.js`) roll random accuracy and reaction time; they chase each cube spawn, re-aiming until they hit. Bots also draw their names from the reserved list: within a room, the room name and all bot names are distinct (a 7-bot room uses the full set of 8). Bot rooms idle while no human is present, and scores reset when the last human leaves.
- In game: players are cubes (1.0 units) on a grey 40x40 plane under a shared static top-down camera pitched at 70 degrees. **Click the plane** to move (simulated server-side at 8 units/s).
- One small **yellow cube** (0.5 units) is alive per room; unclaimed cubes respawn every **5 seconds**. Walking over it scores **+1** and spawns the next one; only one member can claim each cube.
- First to the room's **max score** wins: everyone gets a scoreboard, the room closes (bot rooms are recreated with a fresh reserved name and the same bots), and closing the scoreboard returns you to the lobby.
- The server owns all state; the client only sends intents (`login`, `join_room`, `move`, `chat`, ...) and renders broadcasts (20 Hz).

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

Client to server:
`login {name}` · `chat {text}` · `create_room {name, password?, max_score}` · `join_room {id, password?}` · `leave_room` · `move {x, z}`

Server to client:
`login_ok {name}` / `login_error {reason}` · `lobby {rooms, players}` (pushed every second) · `chat {from, text}` / `chat_history {messages}` · `join_ok {id, color, room}` / `join_error {reason}` / `create_error {reason}` · `state {players, cube}` · `pickup {id, name, score}` · `game_over {room, winner, scores}`

Server files: `server.js` (connections, lobby, chat, room registry), `room.js` (game simulation), `bots.js` (bot controller).
